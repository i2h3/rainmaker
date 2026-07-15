// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

public extension Server {
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
