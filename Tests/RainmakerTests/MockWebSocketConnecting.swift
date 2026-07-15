// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A ``WebSocketConnecting`` test double that vends a queue of pre-scripted ``MockWebSocketChannel`` instances, one per connection attempt.
///
/// Once the queue is exhausted it vends channels that stay open until cancelled, so reconnection after the scripted channels does not spin.
///
final class MockWebSocketConnecting: WebSocketConnecting, @unchecked Sendable {
    ///
    /// Serializes access to the mutable state below.
    ///
    private let lock = NSLock()

    ///
    /// The channels to vend in order, one per ``channel(for:)`` call.
    ///
    private let channels: [MockWebSocketChannel]

    ///
    /// The index of the next channel to vend.
    ///
    private var index = 0

    ///
    /// Create a connector vending the given channels in order.
    ///
    /// - Parameters:
    ///     - channels: The scripted channels, one consumed per connection attempt.
    ///
    init(channels: [MockWebSocketChannel]) {
        self.channels = channels
    }

    func channel(for _: URLRequest) -> any WebSocketChannel {
        lock.lock()
        defer { lock.unlock() }

        guard index < channels.count else {
            return MockWebSocketChannel(frames: [])
        }

        let channel = channels[index]
        index += 1
        return channel
    }
}
