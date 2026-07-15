// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single WebSocket connection, defined as a mockable protocol so the `notify_push` transport can be tested without a live server.
///
/// This mirrors the subset of `URLSessionWebSocketTask` the transport needs; ``URLSession`` vends the production implementation through ``WebSocketConnecting``.
///
public protocol WebSocketChannel: Sendable {
    ///
    /// Start connecting the channel.
    ///
    func resume()

    ///
    /// Send a UTF-8 text frame.
    ///
    /// - Parameters:
    ///     - text: The text to send.
    ///
    func send(_ text: String) async throws

    ///
    /// Receive the next frame, suspending until one arrives.
    ///
    /// - Returns: The received frame.
    ///
    /// - Throws: When the connection fails or is closed, which the transport treats as a disconnect.
    ///
    func receive() async throws -> WebSocketFrame

    ///
    /// Send a ping and wait for its pong.
    ///
    /// - Throws: When the pong is not received, which the transport treats as a dead connection.
    ///
    func sendPing() async throws

    ///
    /// Close the channel.
    ///
    func cancel()
}
