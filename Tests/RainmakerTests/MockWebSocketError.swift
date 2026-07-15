// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Errors thrown by the WebSocket test doubles to simulate a dropped connection.
///
enum MockWebSocketError: Error {
    ///
    /// The connection closed, as ``MockWebSocketChannel`` reports once its scripted frames are exhausted.
    ///
    case closed
}
