// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single message received over a ``WebSocketChannel``.
///
/// The `notify_push` protocol only ever sends text frames, but the binary case is modelled so the abstraction maps cleanly onto `URLSessionWebSocketTask.Message` without discarding anything.
///
public enum WebSocketFrame: Sendable, Equatable {
    ///
    /// A UTF-8 text frame.
    ///
    case text(String)

    ///
    /// A binary frame.
    ///
    case data(Data)
}
