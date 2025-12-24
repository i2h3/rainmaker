// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// HTTP request methods.
///
enum Method: String, RawRepresentable {
    ///
    /// Sending data to a resource.
    ///
    case post = "POST"

    ///
    /// Fetch properties of remote items.
    ///
    case propfind = "PROPFIND"
}
