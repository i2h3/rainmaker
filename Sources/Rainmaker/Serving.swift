// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Represents a Nextcloud instance to interact with.
/// See ``Server`` for a implementation which is ready for use.
///
protocol Serving: Sendable {
    ///
    /// Download a file or a directory including its contents from the server to the local file system.
    ///
    /// This can be used as a one-way synchronization mechanism to replicate remote content locally.
    /// In combination with the enumeration methods, a metadata-only synchronization is also possible.
    ///
    /// This method behaves differently given its arguments:
    ///
    /// | Type | Source | Destination | Force | Behavior |
    /// | - | - | - | - | - |
    /// | File | Exists | Empty | `false` | Download to destination directory |
    /// | File | Exists | Contains file with same name | `false` | Cancel with conflict error |
    /// | File | Exists | Contains file with same name | `true` | Skip if the local file is not older than the remote file, overwrite otherwise |
    /// | File | Changed | Contains file with same name | `true` | Overwrite local file |
    /// | Directory | Exists | Empty | `false` | Download content of source directory to destination directory |
    /// | Directory | Exists | Not empty | `false` | Cancel with conflict error |
    /// | Directory | Exists | Not empty | `true` | Delete local files which are not present in the remote state, replace local files with the state of their remote counterparts, download locally missing files which exist in the remote state  |
    ///
    /// - Parameters:
    ///     - source: The file or root directory to download.
    ///       This can be either a file or a directory.
    ///     - destination: The directory in the local file system to download to.
    ///       For directory downloads, this directory is created automatically when it does not yet exist.
    ///       The content of the source is placed directly into that directory.
    ///     - force: Whether the local state should be overwritten with the remote state or not. This is `false` by default.
    ///
    /// - Throws:
    ///     - If a file is downloaded and an equally named file already exists in the destination directory.
    ///     - If a directory is downloaded and the destination directory is not empty.
    ///
    func download(_ source: String, to destination: URL, force: Bool) async throws

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
    /// Retrieve the information about a single specific item itself.
    ///
    /// This does not retrieve actual content but only metadata.
    ///
    /// - Parameters:
    ///     - path: The item to retrieve the metadata of.
    ///
    /// - Returns: The metadata for the specific item identified by the given path.
    ///
    /// - Throws: Any error that might occur during retrieval of the item properties.
    ///
    func info(_ path: String) async throws -> Item

    ///
    /// Look up the login flow information.
    ///
    /// - Returns: A set of properties to kick off the authentication which yields an app password.
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
