// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Whether a ``MockWebSocketChannel`` was closed, and a wait for that which, like `URLSessionWebSocketTask`, ignores task cancellation.
///
/// It is not an `AsyncStream`, because iterating one does observe cancellation, which is exactly what the production transport cannot rely on.
/// It is `@unchecked Sendable` because ``closed`` and ``waiters`` are only accessed while ``lock`` is held.
///
final class MockWebSocketClosure: @unchecked Sendable {
    ///
    /// Serializes every access to ``closed`` and ``waiters``.
    ///
    private let lock = NSLock()

    ///
    /// Whether ``close()`` was called.
    ///
    private var closed = false

    ///
    /// The continuations of the ``wait()`` calls still suspended, resumed by ``close()``.
    ///
    private var waiters: [CheckedContinuation<Void, Never>] = []

    ///
    /// Whether the channel was closed.
    ///
    var isClosed: Bool {
        lock.withLock {
            closed
        }
    }

    ///
    /// Record the channel as closed and end every ``wait()``, of which only the first call has any effect.
    ///
    func close() {
        let waiting = lock.withLock {
            guard closed == false else {
                return [CheckedContinuation<Void, Never>]()
            }

            closed = true
            let waiting = waiters
            waiters = []
            return waiting
        }

        for waiter in waiting {
            waiter.resume()
        }
    }

    ///
    /// Suspend until the channel is closed, regardless of whether the calling task is cancelled.
    ///
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyClosed = lock.withLock {
                if closed {
                    return true
                }

                waiters.append(continuation)
                return false
            }

            if alreadyClosed {
                continuation.resume()
            }
        }
    }
}
