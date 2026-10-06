// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// Drives a single ``Server/events(_:)`` subscription: with the ``ServerEventTransport/automatic`` transport it discovers whether the server offers `notify_push`, prefers the WebSocket when it does, and otherwise polls, transparently switching and reconnecting so a consumer sees one uninterrupted stream of ``ServerEvent`` values.
///
/// Every event is a re-fetch hint, so the polling fallback simply synthesizes the same hints on a timer that the WebSocket would deliver on change. This is why the two transports are interchangeable from the consumer's point of view.
/// With the ``ServerEventTransport/polling`` transport, and on platforms where ``platformSupportsWebSocket`` is `false`, it only polls and never asks for the capabilities or opens a ``PushNotificationsConnection``.
/// Each WebSocket session is reduced to a ``SessionOutcome``, which decides between reconnecting, retrying the authentication and polling for ``rediscoverInterval`` before looking at the capabilities again.
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
    /// How many consecutive WebSocket connections may end before they authenticated, reported as ``SessionOutcome/disconnected(wasAuthenticated:)`` with `false`, before polling for ``rediscoverInterval`` and then looking at the capabilities again.
    ///
    /// Without this limit an advertised endpoint the client cannot reach, for example behind a proxy which does not forward WebSocket upgrades, would be retried forever with a growing backoff and no events in between. A connection which authenticated resets the count, and so do an authentication rejection, which proves that the socket reached the server, and falling back to polling for any reason, so the count only covers consecutive failures to connect.
    /// This is configurable so tests can exercise the fallback quickly.
    ///
    var maximumConnectionFailures = 3

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
    /// How long each WebSocket connection waits between liveness pings, matching the server's own 30 second ping interval by default.
    ///
    /// This is configurable so tests can exercise the ping loop without waiting for it.
    ///
    var pingInterval: TimeInterval = 30

    ///
    /// How long a liveness ping may wait for its pong before the connection is considered dead and reconnected.
    ///
    var pongTimeout: TimeInterval = 10

    ///
    /// Whether the platform lets an app rely on a WebSocket connection, which decides whether the ``ServerEventTransport/automatic`` transport considers `notify_push` at all.
    ///
    /// It is `false` on watchOS, where the system only grants such connections in narrow circumstances, such as an active audio streaming session, as Apple's technote TN3135 on low-level networking on watchOS describes, and `true` everywhere else.
    ///
    static var platformSupportsWebSocket: Bool {
        #if os(watchOS)
            false
        #else
            true
        #endif
    }

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

        guard options.transport == .automatic, Self.platformSupportsWebSocket else {
            logger.debug("Polling only, without notify_push")

            while Task.isCancelled == false {
                await pollWindow(subjects: options.subjects, interval: options.pollInterval, window: rediscoverInterval, into: continuation)
            }

            continuation.finish()
            return
        }

        var backoffSeconds = initialBackoff
        var authenticationAttempts = 0
        var connectionFailures = 0

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
                connectionFailures = 0
                backoffSeconds = initialBackoff
                await pollWindow(subjects: options.subjects, interval: options.pollInterval, window: rediscoverInterval, into: continuation)
                continue
            }

            logger.debug("Using notify_push for subjects: \(target.subjects.map(\.rawValue).sorted().joined(separator: ", "), privacy: .public)")
            let polledSubjects = options.subjects.subtracting(target.subjects)
            let outcome = await runSession(endpoint: target.endpoint, user: user, password: password, pushedSubjects: target.subjects, polledSubjects: polledSubjects, into: continuation)

            switch outcome {
                case .authenticationRejected:
                    // The socket reached the server, so this ends a run of connections which failed to connect.
                    connectionFailures = 0
                    authenticationAttempts += 1
                    logger.notice("notify_push authentication rejected (attempt \(authenticationAttempts) of \(maximumAuthenticationAttempts))")

                    if authenticationAttempts >= maximumAuthenticationAttempts {
                        authenticationAttempts = 0
                        backoffSeconds = initialBackoff
                        await pollWindow(subjects: options.subjects, interval: options.pollInterval, window: rediscoverInterval, into: continuation)
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(authenticationRetryInterval * 1_000_000_000))
                    }

                case let .disconnected(wasAuthenticated):
                    authenticationAttempts = 0

                    if wasAuthenticated {
                        backoffSeconds = initialBackoff
                        connectionFailures = 0
                    } else {
                        connectionFailures += 1
                    }

                    if connectionFailures >= maximumConnectionFailures {
                        logger.notice("notify_push connection failed \(connectionFailures) times in a row; polling until retry")
                        connectionFailures = 0
                        backoffSeconds = initialBackoff
                        await pollWindow(subjects: options.subjects, interval: options.pollInterval, window: rediscoverInterval, into: continuation)
                        continue
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

        let connection = PushNotificationsConnection(webSocket: server.webSocket, request: request, user: user, password: password, subjects: pushedSubjects, listenFileIDs: options.listenFileIDs, logger: logger, pingInterval: pingInterval, pongTimeout: pongTimeout)
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
    /// With nothing to poll, because there are no subjects or the interval is not positive, it waits out the window instead, so that a caller looping over it does not spin.
    ///
    private func pollWindow(subjects: Set<ServerSubject>, interval: TimeInterval, window: TimeInterval, into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation) async {
        guard interval > 0, subjects.isEmpty == false else {
            try? await Task.sleep(nanoseconds: UInt64(max(window, 0) * 1_000_000_000))
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
