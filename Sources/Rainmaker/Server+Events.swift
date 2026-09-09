// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

public extension Server {
    ///
    /// Observe server-side changes, preferring the `notify_push` WebSocket when the server advertises it and falling back to polling otherwise.
    ///
    /// The transport is chosen automatically from the server's ``PushNotifications`` capability and switched transparently on connection loss, so the returned stream is uninterrupted regardless of which transport is active. Every ``ServerEvent`` is a hint to re-fetch the relevant state (for example calling ``notifications()`` in response to ``ServerEvent/notifications``), never a payload, which is what makes the WebSocket and polling interchangeable to the consumer.
    ///
    /// Credentials are required: the WebSocket handshake and the polled endpoints are user-scoped. A stream created without credentials, or whose credentials are rejected by the server later, finishes by throwing ``RainmakerError/credentialsRequired`` (or ``RainmakerError/unexpectedStatus(code:)`` with `401`) so the client can prompt for re-authentication. Transient network failures are handled internally by reconnecting and are never surfaced.
    ///
    /// The stream ends when the consumer stops iterating it.
    ///
    /// - Parameters:
    ///     - options: Which subjects to observe and at which cadences. See ``ServerEventOptions``.
    ///
    /// - Returns: A stream of ``ServerEvent`` hints.
    ///
    func events(_ options: ServerEventOptions) -> AsyncThrowingStream<ServerEvent, Error> {
        logger.debug("Starting server event stream...")

        return AsyncThrowingStream { continuation in
            guard user != nil, password != nil else {
                continuation.finish(throwing: RainmakerError.credentialsRequired)
                return
            }

            let coordinator = ServerEventCoordinator(server: self, options: options, logger: logger)
            let task = Task {
                await coordinator.run(into: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    ///
    /// A convenience wrapper over ``events(_:)`` for the common case of observing a few subjects at a custom polling interval.
    ///
    /// - Parameters:
    ///     - subjects: The subjects to observe. Defaults to all of them.
    ///     - pollInterval: The polling interval in seconds used when the WebSocket is unavailable. Defaults to 30.
    ///
    /// - Returns: The stream of ``ServerEvent`` values, identical to calling ``events(_:)`` with a matching ``ServerEventOptions``.
    ///
    func events(_ subjects: Set<ServerSubject> = Set(ServerSubject.allCases), pollInterval: TimeInterval = 30) -> AsyncThrowingStream<ServerEvent, Error> {
        events(ServerEventOptions(subjects: subjects, pollInterval: pollInterval))
    }
}
