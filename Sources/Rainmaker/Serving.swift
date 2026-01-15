// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Represents a Nextcloud instance to interact with.
/// See ``Server`` for a implementation which is ready for use.
///
protocol Serving: Sendable {
    ///
    /// Returns items in the given path.
    ///
    /// The use of an asynchronous stream makes it suitable for paginated and continuous processing without waiting for all results to come in first.
    /// This can also avoid peaks in memory usage.
    ///
    /// - Parameters:
    ///     - path: The root directory to enter.
    ///     - recursively: Whether subdirectories should be traversed, too.
    ///
    /// - Throws: Any error that might occur during the listing of a remote directory.
    ///
    /// ## Usage
    ///
    /// You can either process items asynchronously as they arrive:
    ///
    /// ```swift
    /// let stream = try await server.enumerate(at: "/", recursively: false)
    ///
    /// for item in items {
    ///     print(item)
    /// }
    /// ```
    ///
    /// Or you can collect all items in an array before processing them at once:
    ///
    /// ```swift
    /// let stream = try await server.enumerate(at: "/", recursively: false)
    /// var items = [Item]()
    ///
    /// for try await item in stream {
    ///     items.append(item)
    /// }
    /// ```
    ///
    func enumerate(at path: String, recursively: Bool) async throws -> AsyncThrowingStream<Item, Error>

    ///
    /// A convenience wrapper that aggregates all items first before returning.
    ///
    /// > Warning: It is recommended to use the equally named streaming alternative which returns an `AsyncThrowingStream` whenever possible.
    /// Using this method may result in high memory peaks in case of large hierarchies in recursive enumeration.
    ///
    /// - Parameters:
    ///     - path: The root directory to enter.
    ///     - recursively: Whether subdirectories should be traversed, too.
    ///
    /// - Returns: All items found at the given path (and, optionally, in its subdirectories) collected in an array.
    ///
    /// - Throws: Any error that might occur during the listing of a remote directory.
    ///
    func enumerate(at path: String, recursively: Bool) async throws -> [Item]

    ///
    /// Look up the login flow information.
    ///
    func login() async throws -> LoginFlow

    ///
    /// Poll the status of a login flow.
    ///
    /// - Parameters:
    ///     - endpoint: The URL to poll on.
    ///     - token: The unique token of the login flow to check the status of.
    ///
    func poll(_ endpoint: URL, token: String) async throws -> LoginResult
}
