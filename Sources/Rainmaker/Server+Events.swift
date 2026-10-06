// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

public extension Server {
    ///
    /// Observe server-side changes, preferring the `notify_push` WebSocket when the server advertises it and falling back to polling otherwise.
    ///
    /// With the default ``ServerEventTransport/automatic`` transport of ``ServerEventOptions/transport``, the transport is chosen from the server's ``PushNotifications`` capability and switched transparently on connection loss, so the returned stream is uninterrupted regardless of which transport is active. Every ``ServerEvent`` is a hint to re-fetch the relevant state (for example calling ``notifications()`` in response to ``ServerEvent/notifications``), never a payload, which is what makes the WebSocket and polling interchangeable to the consumer.
    ///
    /// The automatic transport falls back to polling for a while and then looks at the capabilities again in three cases: when the server does not advertise `notify_push` for any requested subject, when the WebSocket rejects the credentials three times in a row, and when the WebSocket fails to connect three times in a row without ever authenticating, for example because a proxy does not forward WebSocket upgrades. A connection which authenticated resets that count. On watchOS the automatic transport always polls, because the system only grants WebSocket connections in narrow circumstances.
    ///
    /// The ``ServerEventTransport/polling`` transport only polls at ``ServerEventOptions/pollInterval``: it never requests the capabilities and never opens a WebSocket, so the stream itself sends no requests at all.
    ///
    /// Credentials are required: the WebSocket handshake and the polled endpoints are user-scoped. A stream created without credentials finishes by throwing ``RainmakerError/credentialsRequired``. With the automatic transport on platforms other than watchOS, credentials the server rejects later end the stream by throwing ``RainmakerError/credentialsRequired`` or ``RainmakerError/unexpectedStatus(code:)`` with `401`, so the client can prompt for re-authentication, while polling alone leaves noticing them to the requests the consumer makes in response to the hints. Transient network failures are handled internally by reconnecting and are never surfaced.
    ///
    /// The stream ends when the consumer stops iterating it.
    ///
    /// - Parameters:
    ///     - options: Which subjects to observe, over which transport and at which cadences. See ``ServerEventOptions``.
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
    /// - Returns: The stream of ``ServerEvent`` values, identical to calling ``events(_:)`` with a matching ``ServerEventOptions``, and therefore with the ``ServerEventTransport/automatic`` transport.
    ///
    func events(_ subjects: Set<ServerSubject> = Set(ServerSubject.allCases), pollInterval: TimeInterval = 30) -> AsyncThrowingStream<ServerEvent, Error> {
        events(ServerEventOptions(subjects: subjects, pollInterval: pollInterval))
    }
}
