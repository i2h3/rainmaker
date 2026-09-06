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
    /// The header is omitted for a modification date at or before the Unix epoch and for one which cannot be expressed as a whole number of seconds, in which case the server records the upload time instead.
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
    /// The implementation on ``Server`` defaults `queryItems` to an empty array, so endpoints which are parameterized through the path alone are requested without naming it. Passing an empty array produces exactly the URL a call without any query would.
    ///
    /// - Parameters:
    ///     - path: The path relative to the OCS root, e.g. `"apps/activity/api/v2/activity/all"`.
    ///     - method: The HTTP method to use.
    ///     - queryItems: The query parameters to append, in the order they should appear.
    ///
    func makeOCSRequest(for path: String, method: Method, queryItems: [URLQueryItem]) throws -> URLRequest

    ///
    /// Set up a URL request specifically for the REST API of a server app which is not reachable through OCS.
    ///
    /// Apps commonly expose their own endpoints below `/index.php/apps/`, outside both the OCS root ``makeOCSRequest(for:method:queryItems:)`` targets and the WebDAV roots ``makeWebDAVRequest(for:method:)`` targets. The notes app is one of them, and this is what ``notes()`` is built on.
    ///
    /// Credentials are optional for this call, matching ``makeOCSRequest(for:method:queryItems:)``, because whether an app route requires them is up to the app. No `OCS-APIRequest` header is set, as the request does not go through OCS.
    ///
    /// The implementation on ``Server`` defaults `queryItems` to an empty array, so endpoints which are parameterized through the path alone are requested without naming it. Passing an empty array produces exactly the URL a call without any query would.
    ///
    /// - Parameters:
    ///     - path: The path relative to the apps root (see ``Server/appsAddress``), e.g. `"notes/api/v1/notes"`.
    ///     - method: The HTTP method to use.
    ///     - queryItems: The query parameters to append, in the order they should appear.
    ///
    func makeAppRequest(for path: String, method: Method, queryItems: [URLQueryItem]) throws -> URLRequest

    ///
    /// Set up a URL request specifically for WebDAV interaction.
    ///
    /// The given `path` is resolved relative to the account's WebDAV files root (see ``Server/webDAVPathPrefix``, e.g. `"/remote.php/dav/files/<user>"`).
    ///
    /// Unlike ``makeOCSRequest(for:method:queryItems:)``, credentials are required for this call.
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
    /// List all notes of the authenticated user.
    ///
    /// Notes are provided by the server's notes app which, unlike most of what this library covers, is not part of a Nextcloud installation and has to be installed separately. Whether it is available can be checked in advance via the ``Notes`` capability, e.g. `try await capabilities().contains(Notes.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/notFound``.
    ///
    /// The very same not found error is what a server answers whose `index.php` routing is disabled or whose reverse proxy swallows the route, so those causes cannot be told apart from the response alone.
    ///
    /// An app which is installed but older than ``Notes/minimumAPIVersion`` is reported separately, as ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``. That requirement is checked on every response, because the notes API advertises the versions it serves in a header of its own, and it can be checked in advance through ``Notes/isSupported``.
    ///
    /// The whole collection is retrieved in a single request, because the endpoint returns everything at once unless a chunk size is requested, which this deliberately does not do. Use ``notes(changedSince:)`` to retrieve only what changed since an earlier call.
    ///
    /// > Warning: Every note including its full content is fetched and held in memory at once, so what this costs grows with the size of the account's notes.
    ///
    /// A note the server could not read is listed like any other and does not fail the call. It carries ``Note/hasError`` and its ``Note/content`` is a message about the failure rather than the note's text, so anything which stores what it retrieves has to check that first.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The notes in the order returned by the server.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes() async throws -> [Note]

    ///
    /// List the notes of the authenticated user which changed since a given moment, together with the identifiers of those which did not.
    ///
    /// This is the incremental counterpart of ``notes()`` for a client keeping its own copy of the notes: the server returns every note it recorded a change for at or after `changedSince` in full, and reduces every note it did not to its identifier alone. Both together are the complete set of notes the account has, which is what makes deletions detectable. See ``NoteChanges`` for how the two halves are meant to be applied.
    ///
    /// The moment is sent to the server as its `pruneBefore` parameter, converted to whole seconds since the Unix epoch. A moment at or before the epoch prunes nothing and therefore behaves like ``notes()``.
    ///
    /// > Warning: The server compares this moment against its own record of when it last noticed each note change, which is not the same as that note's ``Note/modification`` date. A note may be from 2020, but when the server only found it today it is not pruned from the response. Never pass a note's ``Note/modification`` back in as this moment; pass one measured on the same clock the server runs on instead, such as when the previous retrieval was made. The API defines the exact value to reuse as the `Last-Modified` header of the previous response, which is the server's own request time and which this library does not surface.
    ///
    /// Everything else, including how an unavailable app surfaces and how a note the server could not read is reported, matches ``notes()``.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, measured against the server's own record of when it last saw a note change rather than against ``Note/modification``.
    ///
    /// - Returns: The changed notes and the identifiers of the unchanged ones.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes(changedSince: Date) async throws -> NoteChanges

    ///
    /// Look up the settings the notes app keeps for the authenticated user.
    ///
    /// These say where the app stores notes and which extension it gives a new one, which matters because notes are ordinary files: the folder is not a fixed name but a value derived from the account's locale by default, so anything which wants to reach notes over WebDAV rather than through ``notes()`` has to ask for it rather than assume it. See ``NotesSettings``.
    ///
    /// The same requirement and the same failure modes as ``notes()`` apply, since this is the same app's API.
    ///
    /// - Returns: The notes app's settings for the authenticated user.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry the settings.
    ///     - Any other error that might occur during retrieval.
    ///
    func notesSettings() async throws -> NotesSettings

    ///
    /// Retrieve one page of the activity stream the server records for the authenticated user.
    ///
    /// Activities are what the server logs about everything happening in an account: files being created, changed and shared, calendar events being scheduled, security relevant events and whatever else an installed app contributes. They are provided by the server's bundled activity app, which is not necessarily installed or enabled. Whether it is available can be checked in advance via the ``Activity`` capability, e.g. `try await capabilities().contains(Activity.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/notFound``.
    ///
    /// The server never returns the whole stream at once, so this returns a single ``ActivityPage`` and leaves paging to the caller: request the next page by passing the previous page's ``ActivityPage/lastGiven`` as `since`, until a page comes back with no ``ActivityPage/items``. Detecting whether anything new happened instead is a matter of comparing ``ActivityPage/firstKnown`` against the value remembered from an earlier call, which is how this pairs with ``ServerEvent/activities``.
    ///
    /// Credentials are required: activities are user-scoped and the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - filter: The subset of the stream to retrieve. Beyond ``ActivityFilter/all``, ``ActivityFilter/own`` and ``ActivityFilter/others`` a server offers further, app-provided filters which can be discovered through ``activityFilters()``. Defaults to ``ActivityFilter/all``.
    ///     - since: The identifier of the activity to continue after, exclusively. Defaults to `0`, which starts at the beginning of the requested sort order.
    ///     - limit: How many activities to retrieve at most. Values are clamped to `1 ... 200`: the server caps the page size at two hundred regardless of what is asked for, and rejects a page size of zero or below with an internal error. Defaults to `50`, matching the server's own default.
    ///     - sort: The direction to walk the stream in. Defaults to ``ActivitySort/newestFirst``.
    ///     - previews: Whether to include the thumbnails of referenced files in ``ActivityItem/previews``. Defaults to `false`, matching the server's own default.
    ///     - objectType: The type of a single object to narrow the stream down to, e.g. `"files"`. Only effective together with `objectId`, and passing both selects ``ActivityFilter/object`` regardless of `filter`. Defaults to `nil`.
    ///     - objectId: The identifier of a single object to narrow the stream down to. Only effective together with `objectType`. Defaults to `nil`.
    ///
    /// - Returns: One page of activities in the order returned by the server, together with the cursors needed to continue.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the activity app is not available on the server or the requested filter does not exist.
    ///     - Any other error that might occur during retrieval.
    ///
    func activities(filter: String, since: Int, limit: Int, sort: ActivitySort, previews: Bool, objectType: String?, objectId: String?) async throws -> ActivityPage

    ///
    /// List the filters the server offers to narrow the activity stream down with.
    ///
    /// Filters are contributed by the server and its installed apps rather than being a fixed list, so this is how the identifiers accepted by the `filter` argument of ``activities(filter:since:limit:sort:previews:objectType:objectId:)`` beyond the well-known ones declared on ``ActivityFilter`` are discovered. Whether the server supports this is advertised under the ``Activity`` capability's `"filters-api"` entry.
    ///
    /// Credentials are required: the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The available filters in the order returned by the server.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the activity app is not available on the server.
    ///     - Any other error that might occur during retrieval.
    ///
    func activityFilters() async throws -> [ActivityFilter]

    ///
    /// Observe server-side changes, preferring the `notify_push` WebSocket when the server advertises it and falling back to polling otherwise.
    ///
    /// The transport is chosen automatically from the server's ``PushNotifications`` capability and switched transparently on connection loss, so the returned stream is uninterrupted regardless of which transport is active. Every ``ServerEvent`` is a hint to re-fetch the relevant state (for example calling ``notifications()`` in response to ``ServerEvent/notifications``), never a payload, which is what makes the WebSocket and polling interchangeable to the consumer.
    ///
    /// Credentials are required: the WebSocket handshake and the polled endpoints are user-scoped. A stream created without credentials, or whose credentials are rejected by the server later, finishes by throwing ``RainmakerError/credentialsRequired`` (or ``RainmakerError/unexpectedStatus(code:)`` with `401`) so the client can prompt for re-authentication. Transient network failures are handled internally by reconnecting and are never surfaced.
    ///
    /// The stream ends when the consumer stops iterating it.
    ///
    /// - Parameters:
    ///     - options: Which subjects to observe and at which cadences. See ``ServerEventOptions``.
    ///
    /// - Returns: A stream of ``ServerEvent`` hints.
    ///
    func events(_ options: ServerEventOptions) -> AsyncThrowingStream<ServerEvent, Error>

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

    ///
    /// Delete the app password this ``Server`` is currently authenticating with, ending the account's session on the server side.
    ///
    /// This targets the self-service `DELETE /ocs/v2.php/core/apppassword` endpoint: the server resolves which app password to revoke from the authenticated request itself, so no identifier is passed or needed.
    /// Because ``Server/user`` and ``Server/password`` are immutable, calling this does not by itself make this ``Server`` instance unusable; it is the caller's responsibility to discard the ``Server`` (and any persisted copy of ``Server/password``) once this call returns.
    ///
    /// A `401 Unauthorized` response means the app password was already invalid (e.g. revoked elsewhere) before this request could even reach the server; a `403 Forbidden` response means the session was not authenticated with an app password at all. Both, like any other non-success response, are surfaced as ``RainmakerError/unexpectedStatus(code:)`` rather than tolerated here: whether such failures should still be treated as an effective local sign-out is a decision left to the caller.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any non-success response.
    ///
    func deleteAppPassword() async throws
}
