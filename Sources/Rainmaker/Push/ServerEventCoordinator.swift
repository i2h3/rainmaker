// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// Drives a single ``Server/events(_:)`` subscription: it discovers whether the server offers `notify_push`, prefers the WebSocket when it does, and otherwise polls, transparently switching and reconnecting so a consumer sees one uninterrupted stream of ``ServerEvent`` values.
///
/// Every event is a re-fetch hint, so the polling fallback simply synthesizes the same hints on a timer that the WebSocket would deliver on change. This is why the two transports are interchangeable from the consumer's point of view.
///
struct ServerEventCoordinator {
    ///
    /// The server to observe.
    ///
    let server: Server

    ///
    /// The subjects and cadences to observe with.
    ///
    let options: ServerEventOptions

    ///
    /// The logger to record coordination activity through.
    ///
    let logger: Logger

    ///
    /// How many consecutive WebSocket authentication rejections are tolerated before giving up on the socket and polling instead.
    ///
    /// This is configurable so tests can exercise the give-up-and-poll path quickly.
    ///
    var maximumAuthenticationAttempts = 3

    ///
    /// How long to wait after a WebSocket authentication rejection before retrying the socket.
    ///
    var authenticationRetryInterval: TimeInterval = 20

    ///
    /// How long to keep polling before re-checking the server's capabilities, so a high-performance backend that appears (or disappears) later is eventually noticed.
    ///
    var rediscoverInterval: TimeInterval = 600

    ///
    /// The longest delay the reconnection backoff grows to.
    ///
    var backoffCeiling: TimeInterval = 60

    ///
    /// The initial reconnection backoff delay, also restored after a connection that had authenticated successfully.
    ///
    var initialBackoff: TimeInterval = 1

    ///
    /// Run the subscription until the consumer stops it or an unrecoverable authentication failure occurs.
    ///
    /// - Parameters:
    ///     - continuation: The stream continuation events are yielded into and finished on.
    ///
    func run(into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation) async {
        guard let user = server.user, let password = server.password else {
            continuation.finish(throwing: RainmakerError.credentialsRequired)
            return
        }

        if options.emitConnectedOnStart {
            continuation.yield(.connected)
        }

        var backoffSeconds = initialBackoff
        var authenticationAttempts = 0

        while Task.isCancelled == false {
            let capabilities: CapabilitySet?

            do {
                capabilities = try await server.capabilities()
            } catch {
                if Self.isUnauthorized(error) {
                    logger.notice("Credentials rejected during discovery; ending stream")
                    continuation.finish(throwing: error)
                    return
                }

                logger.notice("Capabilities discovery failed; polling until retry: \(error.localizedDescription, privacy: .public)")
                capabilities = nil
            }

            let target = capabilities.flatMap { Self.pushTarget(from: $0, requested: options.subjects, accountAddress: server.address) }

            guard let target else {
                logger.debug("notify_push unavailable; polling")
                await pollWindow(subjects: options.subjects, interval: options.pollInterval, window: rediscoverInterval, into: continuation)
                continue
            }

            logger.debug("Using notify_push for subjects: \(target.subjects.map(\.rawValue).sorted().joined(separator: ", "), privacy: .public)")
            let polledSubjects = options.subjects.subtracting(target.subjects)
            let outcome = await runSession(endpoint: target.endpoint, user: user, password: password, pushedSubjects: target.subjects, polledSubjects: polledSubjects, into: continuation)

            switch outcome {
                case .authenticationRejected:
                    authenticationAttempts += 1
                    logger.notice("notify_push authentication rejected (attempt \(authenticationAttempts) of \(maximumAuthenticationAttempts))")

                    if authenticationAttempts >= maximumAuthenticationAttempts {
                        authenticationAttempts = 0
                        await pollWindow(subjects: options.subjects, interval: options.pollInterval, window: rediscoverInterval, into: continuation)
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(authenticationRetryInterval * 1_000_000_000))
                    }

                case let .disconnected(wasAuthenticated):
                    authenticationAttempts = 0

                    if wasAuthenticated {
                        backoffSeconds = initialBackoff
                    }

                    let jittered = backoffSeconds * Double.random(in: 0.8 ... 1.2)
                    try? await Task.sleep(nanoseconds: UInt64(jittered * 1_000_000_000))
                    backoffSeconds = min(backoffSeconds * 2, backoffCeiling)
            }
        }

        continuation.finish()
    }

    ///
    /// Run one WebSocket session together with the polling loops that accompany it, returning once the socket ends.
    ///
    /// The socket carries the pushed subjects and a low-frequency backstop poll covers them as a safety net, while any subject the server does not push is polled at the normal interval. The session ends when the socket does; the poll loops are then cancelled.
    ///
    private func runSession(endpoint: URL, user: String, password: String, pushedSubjects: Set<ServerSubject>, polledSubjects: Set<ServerSubject>, into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation) async -> SessionOutcome {
        var request = URLRequest(url: endpoint)
        request.setValue(server.userAgent, forHTTPHeaderField: "User-Agent")

        let connection = PushNotificationsConnection(webSocket: server.webSocket, request: request, user: user, password: password, subjects: pushedSubjects, listenFileIDs: options.listenFileIDs, logger: logger)
        let backstopInterval = options.backstopPollInterval
        let pollInterval = options.pollInterval

        return await withTaskGroup(of: SessionOutcome?.self) { group in
            group.addTask {
                do {
                    try await connection.open(into: continuation)
                    return .disconnected(wasAuthenticated: false)
                } catch PushNotificationsConnection.Failure.authenticationRejected {
                    return .authenticationRejected
                } catch let PushNotificationsConnection.Failure.disconnected(wasAuthenticated) {
                    return .disconnected(wasAuthenticated: wasAuthenticated)
                } catch {
                    return .disconnected(wasAuthenticated: false)
                }
            }

            group.addTask {
                await Self.poll(subjects: pushedSubjects, interval: backstopInterval, into: continuation)
                return nil
            }

            if polledSubjects.isEmpty == false {
                group.addTask {
                    await Self.poll(subjects: polledSubjects, interval: pollInterval, into: continuation)
                    return nil
                }
            }

            var result = SessionOutcome.disconnected(wasAuthenticated: false)

            for await outcome in group {
                if let outcome {
                    result = outcome
                    break
                }
            }

            group.cancelAll()
            return result
        }
    }

    ///
    /// Emit the given subjects' hints indefinitely at the given interval, stopping when the task is cancelled.
    ///
    private static func poll(subjects: Set<ServerSubject>, interval: TimeInterval, into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation) async {
        guard interval > 0, subjects.isEmpty == false else {
            return
        }

        while Task.isCancelled == false {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }

            for subject in subjects {
                continuation.yield(subject.event)
            }
        }
    }

    ///
    /// Emit the given subjects' hints at the given interval for at most the given window, then return so the caller can re-discover capabilities.
    ///
    private func pollWindow(subjects: Set<ServerSubject>, interval: TimeInterval, window: TimeInterval, into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation) async {
        guard interval > 0, subjects.isEmpty == false else {
            return
        }

        let ticks = max(1, Int((window / interval).rounded()))
        var completed = 0

        while Task.isCancelled == false, completed < ticks {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }

            for subject in subjects {
                continuation.yield(subject.event)
            }

            completed += 1
        }
    }

    ///
    /// Derive the WebSocket target from the server's capabilities, or `nil` when `notify_push` is unavailable, its endpoint is unacceptable, or it pushes none of the requested subjects.
    ///
    static func pushTarget(from capabilities: CapabilitySet, requested: Set<ServerSubject>, accountAddress: URL) -> PushTarget? {
        guard let capability = try? capabilities.get(PushNotifications.self) else {
            return nil
        }

        guard let endpoint = capability.endpoints?.websocket, isAcceptable(endpoint: endpoint, accountAddress: accountAddress) else {
            return nil
        }

        let advertised = Set((capability.type ?? []).compactMap(ServerSubject.init(rawValue:)))
        let subjects = requested.intersection(advertised)

        guard subjects.isEmpty == false else {
            return nil
        }

        return PushTarget(endpoint: endpoint, subjects: subjects)
    }

    ///
    /// Whether a WebSocket endpoint is safe to connect to: `wss://` is always accepted, and cleartext `ws://` only when the account itself is served over plain `http://`.
    ///
    static func isAcceptable(endpoint: URL, accountAddress: URL) -> Bool {
        switch endpoint.scheme {
            case "wss":
                true
            case "ws":
                accountAddress.scheme == "http"
            default:
                false
        }
    }

    ///
    /// Whether an error from a REST call means the credentials are invalid and the stream must end so the client can re-authenticate.
    ///
    static func isUnauthorized(_ error: Error) -> Bool {
        if case RainmakerError.credentialsRequired = error {
            return true
        }

        if case RainmakerError.unexpectedStatus(code: 401) = error {
            return true
        }

        return false
    }
}

// MARK: - Helpers

///
/// The outcome of one WebSocket session, telling ``ServerEventCoordinator`` how to proceed.
///
enum SessionOutcome {
    ///
    /// The server rejected authentication, so the socket should be retried a bounded number of times before falling back to polling.
    ///
    case authenticationRejected

    ///
    /// The socket dropped. `wasAuthenticated` is `true` when it had connected successfully first, which resets the reconnection backoff.
    ///
    case disconnected(wasAuthenticated: Bool)
}

///
/// The resolved WebSocket endpoint and the subset of requested subjects the server actually pushes.
///
struct PushTarget {
    ///
    /// The `wss://` (or accepted `ws://`) endpoint to connect to.
    ///
    let endpoint: URL

    ///
    /// The requested subjects the server advertises over `notify_push`.
    ///
    let subjects: Set<ServerSubject>
}
