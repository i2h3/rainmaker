// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// How a ``MockWebSocketChannel`` answers ``WebSocketChannel/sendPing()``.
///
enum MockPingBehavior {
    ///
    /// Every ping is answered immediately.
    ///
    case pong

    ///
    /// No ping is ever answered: the ping waits until the calling task is cancelled or the channel is closed, which is how the production channel behaves when the framework never reports a ping's outcome.
    ///
    case never

    ///
    /// No ping is ever answered and the ping ignores task cancellation too, ending only when the channel is closed, as a conformer bridging the framework's pong handler without observing cancellation would.
    ///
    case neverIgnoringCancellation
}
