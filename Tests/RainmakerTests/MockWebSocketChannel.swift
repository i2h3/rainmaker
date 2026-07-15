// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A scripted ``WebSocketChannel`` for tests: it replays a fixed sequence of frames, records what was sent, and then either closes or waits until cancelled.
///
/// It is an actor so its mutable state is serialized safely; the synchronous ``resume()`` and ``cancel()`` protocol requirements are satisfied by `nonisolated` no-ops.
///
actor MockWebSocketChannel: WebSocketChannel {
    ///
    /// The frames ``receive()`` replays in order.
    ///
    private let frames: [WebSocketFrame]

    ///
    /// Whether ``receive()`` throws ``MockWebSocketError/closed`` once the frames are exhausted, simulating a drop; when `false` it instead waits until the task is cancelled.
    ///
    private let closesWhenExhausted: Bool

    ///
    /// The index of the next frame to replay.
    ///
    private var index = 0

    ///
    /// Every text frame the transport sent, in order, for handshake assertions.
    ///
    private var sent: [String] = []

    ///
    /// Create a scripted channel.
    ///
    /// - Parameters:
    ///     - frames: The frames to replay in order.
    ///     - closesWhenExhausted: Whether to report a drop once the frames run out. Defaults to `false`, which keeps the connection open until cancelled.
    ///
    init(frames: [WebSocketFrame], closesWhenExhausted: Bool = false) {
        self.frames = frames
        self.closesWhenExhausted = closesWhenExhausted
    }

    nonisolated func resume() {}

    nonisolated func cancel() {}

    func send(_ text: String) async throws {
        sent.append(text)
    }

    func receive() async throws -> WebSocketFrame {
        if index < frames.count {
            let frame = frames[index]
            index += 1
            return frame
        }

        if closesWhenExhausted {
            throw MockWebSocketError.closed
        }

        // Keep the connection "open" until the consuming task is cancelled, then report a close.
        while Task.isCancelled == false {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        throw MockWebSocketError.closed
    }

    func sendPing() async throws {}

    ///
    /// The text frames the transport has sent so far.
    ///
    func sentFrames() -> [String] {
        sent
    }
}
