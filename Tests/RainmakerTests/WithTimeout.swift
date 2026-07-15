// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Thrown by ``withTimeout(seconds:_:)`` when the wrapped operation does not finish in time.
///
struct TimeoutError: Error {}

///
/// Run an asynchronous operation with a timeout so a stalled stream fails the test instead of hanging it forever.
///
/// - Parameters:
///     - seconds: How long to wait before giving up.
///     - operation: The operation to run.
///
/// - Returns: The operation's result when it finishes in time.
///
/// - Throws: ``TimeoutError`` when the deadline elapses first, or whatever the operation throws.
///
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        guard let result = try await group.next() else {
            throw TimeoutError()
        }

        group.cancelAll()
        return result
    }
}
