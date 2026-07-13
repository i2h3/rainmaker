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
    /// Upload a file or a directory including its contents from the local file system to the server.
    ///
    /// This is the counterpart of ``download(_:to:force:)`` and can be used as a one-way synchronization mechanism to replicate local content remotely.
    ///
    /// This method behaves differently given its arguments:
    ///
    /// | Type | Source | Destination | Force | Behavior |
    /// | - | - | - | - | - |
    /// | File | Exists | No equally named remote item | `false` | Upload into the destination directory |
    /// | File | Exists | Contains item with same name | `false` | Cancel with conflict error |
    /// | File | Exists | Contains item with same name | `true` | Skip if the remote file is not older than the local file, overwrite otherwise |
    /// | File | Changed | Contains item with same name | `true` | Overwrite remote file |
    /// | Directory | Exists | Empty or absent | `false` | Upload content of source directory into destination directory |
    /// | Directory | Exists | Not empty | `false` | Cancel with conflict error |
    /// | Directory | Exists | Not empty | `true` | Delete remote items which are not present in the local state, replace remote files with the state of their local counterparts, upload remotely missing files which exist in the local state |
    ///
    /// The local modification date of an uploaded file is preserved on the server via the `X-OC-Mtime` header so that future synchronization runs can detect unchanged files.
    ///
    /// - Parameters:
    ///     - source: The file or root directory in the local file system to upload.
    ///       This can be either a file or a directory.
    ///     - destination: The remote directory to upload into.
    ///       For directory uploads, this directory is created automatically when it does not yet exist.
    ///       The content of the source is placed directly into that directory.
    ///     - force: Whether the remote state should be overwritten with the local state or not. This is `false` by default.
    ///
    /// - Throws:
    ///     - ``RainmakerError/notFound`` when the local source does not exist.
    ///     - ``RainmakerError/fileAlreadyExists(_:)`` when a file is uploaded and an equally named remote item already exists while `force` is `false`.
    ///     - ``RainmakerError/directoryNotEmpty`` when a directory is uploaded into a non-empty remote directory while `force` is `false`.
    ///
    func upload(_ source: URL, to destination: String, force: Bool) async throws

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
    /// Create a new directory at the given remote path.
    ///
    /// Only a single directory level is created, so the parent directory must already exist.
    /// This maps to a WebDAV `MKCOL` request against the target path.
    ///
    /// - Parameters:
    ///     - path: The remote path of the directory to create.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/fileAlreadyExists(_:)`` when a file or directory already exists at the given path.
    ///     - ``RainmakerError/notFound`` when the parent directory does not exist.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other unexpected server response.
    ///
    func createDirectory(_ path: String) async throws

    ///
    /// Delete a remote item.
    ///
    /// Deleting a directory removes it together with all of its contents recursively.
    /// On Nextcloud, deleted items are moved to the server-side trash bin and can be restored there.
    ///
    /// - Parameters:
    ///     - path: The remote path of the file or directory to delete.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when no item exists at the given path.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///
    func delete(_ path: String) async throws

    ///
    /// Relocate (move and/or rename) a remote file or directory to another remote path on the server.
    ///
    /// Both `source` and `destination` are remote paths on the same account.
    /// This performs a server-side WebDAV `MOVE`; nothing is downloaded locally.
    /// It works identically for files and for directories (collections), relocating the whole subtree in a single request.
    /// Renaming is just a move whose destination has a different last path component.
    ///
    /// This method behaves differently given its arguments:
    ///
    /// | Source | Destination | Overwrite | Behavior |
    /// | - | - | - | - |
    /// | Exists | Free | any | Relocate the item to the destination path |
    /// | Exists | Occupied | `true` | Replace the existing destination with the source |
    /// | Exists | Occupied | `false` | Cancel with conflict error |
    /// | Missing | any | any | Cancel with not found error |
    ///
    /// - Parameters:
    ///     - source: The remote path of the file or directory to relocate.
    ///     - destination: The remote target path. A differing last path component renames the item.
    ///     - overwrite: Whether an item already present at the destination may be replaced.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the source or the destination's parent directory does not exist.
    ///     - ``RainmakerError/destinationExists(_:)`` when the destination is occupied and `overwrite` is `false`.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///
    func move(_ source: String, to destination: String, overwrite: Bool) async throws

    ///
    /// List the items currently in the user's trash bin.
    ///
    /// On Nextcloud, deleting an item moves it to the trash bin from where it can be restored or permanently removed.
    /// Whether the trash bin is available can be checked in advance via the ``Trashing`` capability, e.g. `try await capabilities().get(Trashing.self)?.undelete`.
    ///
    /// - Returns: The trashed items in the order returned by the server.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the trash bin is unavailable.
    ///     - Any other error that might occur during retrieval.
    ///
    func trash() async throws -> [TrashItem]

    ///
    /// Restore a trashed item back to its original location.
    ///
    /// The server always restores the item to its original location (``TrashItem/originalLocation``) regardless of the identifier passed.
    ///
    /// - Parameters:
    ///     - id: The identifier of the trashed item to restore, as exposed by ``TrashItem/id``.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when no such trashed item exists or the trash bin is unavailable.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///
    func restore(_ id: String) async throws

    ///
    /// Restore a trashed item back to its original location.
    ///
    /// This is a convenience wrapper around ``restore(_:)-(String)`` using the item's ``TrashItem/id``.
    ///
    /// - Parameters:
    ///     - item: The trashed item to restore.
    ///
    func restore(_ item: TrashItem) async throws

    ///
    /// Permanently empty the entire trash bin.
    ///
    /// This removes every trashed item and cannot be undone.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any non-success response.
    ///
    func emptyTrash() async throws

    ///
    /// Set up a URL request specifically for Nextcloud OCS API interaction.
    ///
    /// Credentials are optional for this call.
    ///
    func makeOCSRequest(for path: String, method: Method) throws -> URLRequest

    ///
    /// Set up a URL request specifically for WebDAV interaction.
    ///
    /// The given `path` is resolved relative to the account's WebDAV files root (see ``Server/webDAVPathPrefix``, e.g. `"/remote.php/dav/files/<user>"`).
    ///
    /// Unlike ``makeOCSRequest(for:method:)``, credentials are required for this call.
    ///
    /// - Throws: ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///
    func makeWebDAVRequest(for path: String, method: Method) throws -> URLRequest

    ///
    /// Fetch the capabilities advertised by the server.
    ///
    /// Works with or without credentials: when this ``Serving`` was created without a user name and password the capabilities are fetched anonymously, which returns the subset of capabilities the server exposes to unauthenticated clients.
    /// When credentials are present the full, account-scoped set is returned.
    ///
    /// - Returns: A ``CapabilitySet`` exposing the server ``Version`` and the advertised capabilities, queryable via ``CapabilitySet/get(_:)``.
    ///
    func capabilities() async throws -> CapabilitySet

    ///
    /// Fetch the apps navigation entries the server advertises for the authenticated user.
    ///
    /// These are the server apps (e.g. Files, Photos, Activity) which a client can surface in its own navigation.
    /// Credentials are required: the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The navigation items in the order returned by the server.
    ///
    /// - Throws: ``RainmakerError/credentialsRequired`` when no credentials are set, or any error that might occur during retrieval.
    ///
    func navigation() async throws -> [NavigationItem]

    ///
    /// List the notifications currently queued for the authenticated user.
    ///
    /// These are provided by the server's bundled notifications app, which is not necessarily installed or enabled. Whether it is available can be checked in advance via the ``Notifications`` capability, e.g. `try await capabilities().contains(Notifications.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/notFound``.
    ///
    /// Downstream projects can derive whether there are any notifications and how many from the returned array via `isEmpty` and `count`.
    ///
    /// Credentials are required: notifications are user-scoped and the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The queued notifications in the order returned by the server, newest first.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notifications app is not available on the server.
    ///     - Any other error that might occur during retrieval.
    ///
    func notifications() async throws -> [NotificationItem]

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
