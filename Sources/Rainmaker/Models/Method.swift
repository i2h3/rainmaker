// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// HTTP request methods.
///
public enum Method: String, RawRepresentable {
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

    ///
    /// Create a new collection (directory) on a WebDAV server.
    ///
    case mkcol = "MKCOL"

    ///
    /// Delete a remote item.
    ///
    case delete = "DELETE"
}
