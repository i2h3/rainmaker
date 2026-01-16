// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// HTTP request methods.
///
enum Method: String, RawRepresentable {
    ///
    /// Fetching a resource.
    ///
    case get = "GET"

    ///
    /// Sending data to a resource.
    ///
    case post = "POST"

    ///
    /// Fetch properties of remote items.
    ///
    case propfind = "PROPFIND"
}
