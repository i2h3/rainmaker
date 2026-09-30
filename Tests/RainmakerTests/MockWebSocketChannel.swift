// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A scripted ``WebSocketChannel`` for tests: it replays a fixed sequence of frames, records what was sent, answers pings as scripted, and then either closes or waits until cancelled or closed.
///
/// It is an actor so its mutable state is serialized safely; the synchronous ``resume()`` protocol requirement is satisfied by a `nonisolated` no-op, and ``cancel()`` records the close in ``closure``, which ends any wait for it.
/// By default its waits observe task cancellation, which `URLSessionWebSocketTask` does not; ``ignoresTaskCancellation`` makes ``receive()`` behave like the latter, so the transport's teardown is exercised against the framework it actually runs on.
///
actor MockWebSocketChannel: WebSocketChannel {
    ///
    /// The frames ``receive()`` replays in order.
    ///
    private let frames: [WebSocketFrame]

    ///
    /// Whether ``receive()`` throws ``MockWebSocketError/closed`` once the frames are exhausted, simulating a drop; when `false` it instead waits until the task is cancelled or the channel is closed, or only until the latter when ``ignoresTaskCancellation`` is set.
    ///
    private let closesWhenExhausted: Bool

    ///
    /// Whether ``receive()`` ignores task cancellation once the frames are exhausted and ends only when the channel is closed, as `URLSessionWebSocketTask` does.
    ///
    private let ignoresTaskCancellation: Bool

    ///
    /// How pings are answered.
    ///
    private let pingBehavior: MockPingBehavior

    ///
    /// Records whether ``cancel()`` was called and ends the waits for that, which the transport relies on to end a session.
    ///
    nonisolated let closure = MockWebSocketClosure()

    ///
    /// How many pings were sent so far.
    ///
    private var pings = 0

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
    ///     - closesWhenExhausted: Whether to report a drop once the frames run out. Defaults to `false`, which keeps the connection open until cancelled or closed.
    ///     - ignoresTaskCancellation: Whether keeping the connection open ignores task cancellation and ends only when the channel is closed, as `URLSessionWebSocketTask` does. Defaults to `false`.
    ///     - pingBehavior: How pings are answered. Defaults to answering every ping.
    ///
    init(frames: [WebSocketFrame], closesWhenExhausted: Bool = false, ignoresTaskCancellation: Bool = false, pingBehavior: MockPingBehavior = .pong) {
        self.frames = frames
        self.closesWhenExhausted = closesWhenExhausted
        self.ignoresTaskCancellation = ignoresTaskCancellation
        self.pingBehavior = pingBehavior
    }

    nonisolated func resume() {}

    nonisolated func cancel() {
        closure.close()
    }

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

        if ignoresTaskCancellation {
            // Keep the connection "open" until the channel is closed, whether the consuming task is cancelled or not.
            await closure.wait()
            throw MockWebSocketError.closed
        }

        // Keep the connection "open" until the consuming task is cancelled or the channel is closed, then report a close.
        while Task.isCancelled == false, closure.isClosed == false {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        throw MockWebSocketError.closed
    }

    func sendPing() async throws {
        pings += 1

        switch pingBehavior {
            case .pong:
                return

            case .never:
                // Observes cancellation through the sleep, as the production channel's ping does.
                while closure.isClosed == false {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }

                throw MockWebSocketError.closed

            case .neverIgnoringCancellation:
                await closure.wait()
                throw MockWebSocketError.closed
        }
    }

    ///
    /// How many pings the transport has sent so far.
    ///
    func pingCount() -> Int {
        pings
    }

    ///
    /// The text frames the transport has sent so far.
    ///
    func sentFrames() -> [String] {
        sent
    }
}
