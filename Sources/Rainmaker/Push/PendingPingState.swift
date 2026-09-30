// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Where one ``PendingPing`` stands between being sent and delivering its single outcome to the task waiting for it.
///
/// Every case but ``idle`` and ``waiting(_:)`` is final for the ping, which is what lets ``PendingPing`` resume the waiting task exactly once no matter how often and in which order the pong handler and the task's cancellation report.
///
enum PendingPingState {
    ///
    /// The waiting task has not installed its continuation yet, so the ping has not been sent either.
    ///
    case idle

    ///
    /// The ping was sent and its continuation is waiting for the first outcome.
    ///
    case waiting(CheckedContinuation<Void, any Error>)

    ///
    /// The waiting task was cancelled before any outcome arrived, so its continuation is resumed with `CancellationError`, either when the cancellation finds it waiting or when it is installed afterwards.
    ///
    case cancelled

    ///
    /// The pong handler delivered its first outcome to the waiting task, so any later one is dropped.
    ///
    case resolved
}
