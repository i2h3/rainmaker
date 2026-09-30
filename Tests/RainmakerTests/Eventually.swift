// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Poll a condition until it holds, giving up once the deadline passes.
///
/// Unlike ``withTimeout(seconds:_:)`` this also bounds a wait for something that does not observe task cancellation, such as a continuation which is never resumed: a task group waits for all of its children, so racing such an operation against a timer hangs instead of failing, while polling never waits on the operation at all.
/// The deadline is a guard against a hang, not an assertion about speed, and therefore generous on purpose.
///
/// - Parameters:
///     - seconds: How long to keep polling before giving up.
///     - condition: The condition to wait for, evaluated on the calling task.
///
/// - Returns: Whether the condition held before the deadline passed.
///
func eventually(within seconds: Double = 30, _ condition: () async -> Bool) async throws -> Bool {
    let deadline = Date().addingTimeInterval(seconds)

    while await condition() == false {
        guard Date() < deadline else {
            return false
        }

        try await Task.sleep(nanoseconds: 2_000_000)
    }

    return true
}
