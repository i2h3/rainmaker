// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Represents a Nextcloud instance to interact with.
/// See ``Server`` for a implementation which is ready for use.
///
public protocol Serving: Sendable {
    ///
    /// The base address of the Nextcloud instance.
    ///
    var address: URL { get }

    ///
    /// The app password to use for authentication.
    ///
    var password: String { get }

    ///
    /// The user to authenticate as.
    ///
    var user: String { get }

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
}
