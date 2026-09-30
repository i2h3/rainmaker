// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A value shared between a test and the closures it hands to the code under test, which may call them from any thread.
///
/// It is `@unchecked Sendable` because ``value`` is only accessed while ``lock`` is held, which is what makes it safe to capture into a `@Sendable` closure the way a mutable local variable cannot be.
///
final class LockedValue<Value>: @unchecked Sendable {
    ///
    /// Serializes every access to ``value``.
    ///
    private let lock = NSLock()

    ///
    /// The shared value, only ever accessed while ``lock`` is held.
    ///
    private var value: Value

    ///
    /// Share the given initial value.
    ///
    /// - Parameters:
    ///     - value: The initial value.
    ///
    init(_ value: Value) {
        self.value = value
    }

    ///
    /// Read the current value.
    ///
    /// - Returns: A copy of the current value.
    ///
    func get() -> Value {
        lock.withLock {
            value
        }
    }

    ///
    /// Replace the current value.
    ///
    /// - Parameters:
    ///     - newValue: The value to store.
    ///
    func set(_ newValue: Value) {
        lock.withLock {
            value = newValue
        }
    }

    ///
    /// Read and change the value in one step no other thread can interleave with.
    ///
    /// - Parameters:
    ///     - body: Changes the value in place and returns a result.
    ///
    /// - Returns: What `body` returned.
    ///
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock {
            body(&value)
        }
    }
}
