// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// One ping sent by ``URLSessionWebSocketChannel/sendPing()`` which resumes the task waiting for it exactly once.
///
/// `URLSessionWebSocketTask.sendPing(pongReceiveHandler:)` calls its handler more than once for a single ping, even concurrently from different queues, when the connection is torn down between ping and pong, which Apple acknowledged as a bug of its own.
/// Resuming a `CheckedContinuation` a second time terminates the process, so the handler's outcomes are funnelled through the ``PendingPingState`` held here and only the first one reaches the waiting task.
/// The handler is also known never to be called at all, which is why the waiting task's cancellation competes for the same single outcome: that is what lets ``PushNotificationsConnection`` end a session whose pong never arrives.
///
/// It is `@unchecked Sendable` because ``state`` is only read and written while ``lock`` is held; `Mutex` and `OSAllocatedUnfairLock` would express that to the compiler but are not available at every deployment target of this package.
///
final class PendingPing: @unchecked Sendable {
    ///
    /// Serializes every access to ``state``, which the pong handler, the waiting task and its cancellation handler reach from different threads.
    ///
    private let lock = NSLock()

    ///
    /// Where the ping stands, only ever accessed while ``lock`` is held.
    ///
    private var state = PendingPingState.idle

    ///
    /// The logger recording the outcomes which arrive after the one that resumed the waiting task.
    ///
    private let logger: Logger

    ///
    /// Prepare a ping which is not sent before ``wait(function:sending:)`` is called.
    ///
    /// - Parameters:
    ///     - logger: The logger to record dropped outcomes through, which should be the one of the channel sending the ping.
    ///
    init(logger: Logger) {
        self.logger = logger
    }

    ///
    /// Send the ping and suspend until its first outcome arrives or the calling task is cancelled, whichever happens first.
    ///
    /// - Parameters:
    ///     - function: The name a continuation misuse or leak message reports, which defaults to the caller's so such a message names the method sending the ping rather than this one.
    ///     - send: Sends the ping and hands the given pong handler to the framework; it is not called at all when the calling task is already cancelled.
    ///
    /// - Throws: The first error the pong handler reports, or `CancellationError` when the calling task is cancelled first.
    ///
    func wait(function: String = #function, sending send: (@escaping @Sendable ((any Error)?) -> Void) -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(function: function) { (continuation: CheckedContinuation<Void, any Error>) in
                guard install(continuation) else {
                    return
                }

                send { error in
                    self.resolve(error)
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    ///
    /// Deliver one outcome of the pong handler, of which only the first resumes the waiting task.
    ///
    /// - Parameters:
    ///     - error: The error the pong handler reported, or `nil` when the pong arrived.
    ///
    /// - Returns: Whether this outcome resumed the waiting task.
    ///
    @discardableResult
    func resolve(_ error: (any Error)?) -> Bool {
        let previous = lock.withLock {
            let previous = state

            if case .waiting = previous {
                state = .resolved
            }

            return previous
        }

        switch previous {
            case let .waiting(continuation):
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }

                return true

            case .cancelled:
                // Expected: closing the channel of a cancelled session makes the framework report the ping it still had outstanding.
                logger.debug("Dropped the outcome of a cancelled ping: \(Self.describe(error), privacy: .public)")
                return false

            case .resolved:
                logger.notice("Dropped a repeated pong handler call for a ping which already resumed its task: \(Self.describe(error), privacy: .public)")
                return false

            case .idle:
                // Unreachable: the pong handler is only handed out once the continuation is installed.
                logger.error("Dropped a pong handler call for a ping which was never sent: \(Self.describe(error), privacy: .public)")
                return false
        }
    }

    ///
    /// Install the continuation of the waiting task unless the task was cancelled first.
    ///
    /// - Parameters:
    ///     - continuation: The continuation to resume with the first outcome.
    ///
    /// - Returns: Whether the continuation was installed and the ping should be sent; when `false`, the continuation was already resumed with `CancellationError`.
    ///
    private func install(_ continuation: CheckedContinuation<Void, any Error>) -> Bool {
        let installed = lock.withLock {
            guard case .idle = state else {
                return false
            }

            state = .waiting(continuation)
            return true
        }

        if installed == false {
            logger.debug("Did not send a ping for a task cancelled before it could")
            continuation.resume(throwing: CancellationError())
        }

        return installed
    }

    ///
    /// Resume the waiting task with `CancellationError` unless an outcome already did, and drop every outcome arriving afterwards.
    ///
    private func cancel() {
        let previous = lock.withLock {
            let previous = state

            switch previous {
                case .idle, .waiting:
                    state = .cancelled

                case .cancelled, .resolved:
                    break
            }

            return previous
        }

        if case let .waiting(continuation) = previous {
            logger.debug("Cancelled a ping still waiting for its pong")
            continuation.resume(throwing: CancellationError())
        }
    }

    ///
    /// Describe an outcome of the pong handler without any user data, so it can be logged publicly.
    ///
    /// - Parameters:
    ///     - error: The error the pong handler reported, or `nil` when the pong arrived.
    ///
    /// - Returns: `"pong received"`, or the error's domain, code and description.
    ///
    private static func describe(_ error: (any Error)?) -> String {
        guard let error else {
            return "pong received"
        }

        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }
}
