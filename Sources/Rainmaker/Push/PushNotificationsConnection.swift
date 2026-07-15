// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// One lifetime of a `notify_push` WebSocket connection: it authenticates, then maps incoming frames to ``ServerEvent`` values yielded into a stream until the connection ends.
///
/// It is a value type carrying only immutable, `Sendable` inputs and therefore needs no isolation of its own; ``ServerEventCoordinator`` owns the reconnection state and decides when to open a new connection.
///
struct PushNotificationsConnection {
    ///
    /// Why a connection ended, so the coordinator can decide whether to reconnect, fall back to polling, or give up.
    ///
    enum Failure: Error {
        ///
        /// The server rejected authentication with an `err:` frame or an authentication timeout, carrying the server's message.
        ///
        case authenticationRejected(String)

        ///
        /// The connection dropped. `wasAuthenticated` is `true` when the drop happened after a successful handshake, which lets the coordinator reset its reconnection backoff.
        ///
        case disconnected(wasAuthenticated: Bool)
    }

    ///
    /// How long to wait between liveness pings, matching the server's own 30 second ping interval.
    ///
    private static let pingInterval: TimeInterval = 30

    ///
    /// The connector vending the underlying channel.
    ///
    let webSocket: any WebSocketConnecting

    ///
    /// The request describing the `wss://` endpoint.
    ///
    let request: URLRequest

    ///
    /// The Nextcloud user name to authenticate as.
    ///
    let user: String

    ///
    /// The app password to authenticate with.
    ///
    let password: String

    ///
    /// The subjects whose frames should be forwarded; others are ignored.
    ///
    let subjects: Set<ServerSubject>

    ///
    /// Whether to opt into per-file identifiers via `listen notify_file_id`.
    ///
    let listenFileIDs: Bool

    ///
    /// The logger to record connection activity through.
    ///
    let logger: Logger

    ///
    /// Open the connection, authenticate, and pump events into `continuation` until the connection ends.
    ///
    /// - Parameters:
    ///     - continuation: The stream continuation to yield ``ServerEvent`` values into, including ``ServerEvent/connected`` once authenticated.
    ///
    /// - Throws: A ``Failure`` describing why the connection ended.
    ///
    func open(into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation) async throws {
        logger.debug("Opening notify_push connection...")
        let channel = webSocket.channel(for: request)
        channel.resume()

        var authenticated = false

        do {
            try await channel.send(user)
            try await channel.send(password)
            try await authenticate(on: channel)
            authenticated = true
            logger.debug("notify_push connection authenticated")

            if listenFileIDs {
                try await channel.send("listen notify_file_id")
            }

            continuation.yield(.connected)
            try await pump(channel: channel, into: continuation)

            // The pump only returns by throwing; reaching here means the read loop ended without error, which is still a disconnect.
            channel.cancel()
            throw Failure.disconnected(wasAuthenticated: true)
        } catch let failure as Failure {
            channel.cancel()
            throw failure
        } catch {
            channel.cancel()
            throw Failure.disconnected(wasAuthenticated: authenticated)
        }
    }

    ///
    /// Read frames until the server confirms authentication, throwing on rejection.
    ///
    private func authenticate(on channel: any WebSocketChannel) async throws {
        while true {
            let frame = try await channel.receive()

            guard case let .text(text) = frame else {
                continue
            }

            if text == "authenticated" {
                return
            }

            if text.hasPrefix("err: ") {
                throw Failure.authenticationRejected(String(text.dropFirst("err: ".count)))
            }

            if text == "Authentication timeout" {
                throw Failure.authenticationRejected(text)
            }

            // Any other frame before authentication is unexpected and ignored.
        }
    }

    ///
    /// Run the read loop and the liveness ping loop concurrently until either ends, which ends the connection.
    ///
    private func pump(channel: any WebSocketChannel, into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let subjects = subjects
            let logger = logger

            group.addTask {
                try await Self.read(from: channel, subjects: subjects, into: continuation, logger: logger)
            }

            group.addTask {
                try await Self.ping(on: channel)
            }

            // The first task to finish or throw ends the session; cancel the other and surface the outcome.
            try await group.next()
            group.cancelAll()
        }
    }

    ///
    /// Continuously receive frames, mapping each to a ``ServerEvent`` and yielding it.
    ///
    private static func read(from channel: any WebSocketChannel, subjects: Set<ServerSubject>, into continuation: AsyncThrowingStream<ServerEvent, Error>.Continuation, logger: Logger) async throws {
        while true {
            let frame = try await channel.receive()

            guard case let .text(text) = frame else {
                continue
            }

            logger.debug("notify_push frame: \(text, privacy: .public)")

            if let event = event(forFrame: text, subjects: subjects) {
                continuation.yield(event)
            }
        }
    }

    ///
    /// Send a liveness ping on the given interval, throwing when a pong fails to arrive.
    ///
    private static func ping(on channel: any WebSocketChannel) async throws {
        while true {
            try await Task.sleep(nanoseconds: UInt64(pingInterval * 1_000_000_000))
            try await channel.sendPing()
        }
    }

    ///
    /// Map a `notify_push` text frame to the ``ServerEvent`` it signals, or `nil` when the frame concerns a subject that was not requested.
    ///
    /// Unrecognized frames are surfaced as ``ServerEvent/custom(type:body:)`` so third-party push types are not silently dropped.
    ///
    static func event(forFrame frame: String, subjects: Set<ServerSubject>) -> ServerEvent? {
        if frame == "notify_notification" {
            return subjects.contains(.notifications) ? .notifications : nil
        }

        if frame == "notify_activity" {
            return subjects.contains(.activities) ? .activities : nil
        }

        if frame == "notify_file" {
            return subjects.contains(.files) ? .files(ids: nil) : nil
        }

        if frame.hasPrefix("notify_file_id ") {
            guard subjects.contains(.files) else {
                return nil
            }

            let payload = String(frame.dropFirst("notify_file_id ".count))
            let ids = try? JSONDecoder().decode([Int].self, from: Data(payload.utf8))
            return .files(ids: ids)
        }

        // The pre-authentication acknowledgement can be ignored if it ever arrives here.
        if frame == "authenticated" || frame.isEmpty {
            return nil
        }

        let parts = frame.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let type = String(parts[0])
        let body = parts.count > 1 ? String(parts[1]) : nil
        return .custom(type: type, body: body)
    }
}
