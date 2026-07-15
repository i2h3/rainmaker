// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The ability to open a ``WebSocketChannel`` for a request, defined as a mockable protocol so the `notify_push` transport can be tested without a live server.
///
/// This is the WebSocket counterpart to ``Requesting`` and is satisfied in production by ``URLSession``.
///
public protocol WebSocketConnecting: Sendable {
    ///
    /// Create a channel for the given request without starting it yet.
    ///
    /// - Parameters:
    ///     - request: The request describing the WebSocket endpoint to connect to.
    ///
    /// - Returns: A channel which begins connecting once ``WebSocketChannel/resume()`` is called.
    ///
    func channel(for request: URLRequest) -> any WebSocketChannel
}
