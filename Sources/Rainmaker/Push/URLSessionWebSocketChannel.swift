// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// The production ``WebSocketChannel`` backed by a `URLSessionWebSocketTask`.
///
/// It is `@unchecked Sendable` because it wraps a `URLSessionWebSocketTask`, whose send, receive, ping and cancel operations are safe to call from concurrent tasks, mirroring the reasoning behind ``Server``'s `nonisolated(unsafe)` file manager.
///
/// The one callback it bridges itself, the pong handler, goes through a ``PendingPing``, because the framework may call that handler more than once for a single ping or not at all.
///
final class URLSessionWebSocketChannel: WebSocketChannel, @unchecked Sendable {
    ///
    /// The underlying task performing the connection.
    ///
    private let task: URLSessionWebSocketTask

    ///
    /// The logger recording what ``PendingPing`` drops of the pong handler's outcomes.
    ///
    private let logger = Logger(category: "URLSessionWebSocketChannel")

    ///
    /// Wrap the given task.
    ///
    /// - Parameters:
    ///     - task: The WebSocket task to drive, created but not yet resumed.
    ///
    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func resume() {
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> WebSocketFrame {
        let message = try await task.receive()

        switch message {
            case let .string(text):
                return .text(text)
            case let .data(data):
                return .data(data)
            @unknown default:
                return .data(Data())
        }
    }

    func sendPing() async throws {
        try await PendingPing(logger: logger).wait { handler in
            task.sendPing(pongReceiveHandler: handler)
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
