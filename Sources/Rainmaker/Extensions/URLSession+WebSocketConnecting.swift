// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension URLSession: WebSocketConnecting {
    public func channel(for request: URLRequest) -> any WebSocketChannel {
        URLSessionWebSocketChannel(task: webSocketTask(with: request))
    }
}
