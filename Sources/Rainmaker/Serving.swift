// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Represents a Nextcloud instance to interact with.
/// See ``Server`` for an implementation which is ready for use.
///
/// The requirements carry one-line abstracts only.
/// Their full documentation lives on the corresponding methods of ``Server``, because this protocol is internal and therefore absent from the published reference, which is generated from public symbols alone.
///
protocol Serving: Sendable {
    ///
    /// Download a file or a directory including its contents from the server to the local file system.
    ///
    func download(_ source: String, to destination: URL, force: Bool) async throws

    ///
    /// Upload a file or a directory including its contents from the local file system to the server.
    ///
    func upload(_ source: URL, to destination: String, force: Bool, chunkSize: Int) async throws

    ///
    /// Returns items in the given path.
    ///
    func enumerate(at path: String, recursively: Bool) async throws -> AsyncThrowingStream<Item, Error>

    ///
    /// A convenience wrapper that aggregates all items first before returning.
    ///
    func enumerate(at path: String, recursively: Bool) async throws -> [Item]

    ///
    /// Retrieve the information about a single specific item itself.
    ///
    func info(_ path: String) async throws -> Item

    ///
    /// Create a new directory at the given remote path.
    ///
    func createDirectory(_ path: String) async throws

    ///
    /// Delete a remote item.
    ///
    func delete(_ path: String) async throws

    ///
    /// Relocate (move and/or rename) a remote file or directory to another remote path on the server.
    ///
    func move(_ source: String, to destination: String, overwrite: Bool) async throws

    ///
    /// List the items currently in the user's trash bin.
    ///
    func trash() async throws -> [TrashItem]

    ///
    /// Restore a trashed item back to its original location.
    ///
    func restore(_ id: String) async throws

    ///
    /// Restore a trashed item back to its original location.
    ///
    func restore(_ item: TrashItem) async throws

    ///
    /// Permanently empty the entire trash bin.
    ///
    func emptyTrash() async throws

    ///
    /// Set up a URL request specifically for Nextcloud OCS API interaction.
    ///
    func makeOCSRequest(for path: String, method: Method, queryItems: [URLQueryItem]) throws -> URLRequest

    ///
    /// Set up a URL request specifically for the REST API of a server app which is not reachable through OCS.
    ///
    func makeAppRequest(for path: String, method: Method, queryItems: [URLQueryItem]) throws -> URLRequest

    ///
    /// Set up a URL request specifically for WebDAV interaction.
    ///
    func makeWebDAVRequest(for path: String, method: Method) throws -> URLRequest

    ///
    /// Fetch the capabilities advertised by the server.
    ///
    func capabilities() async throws -> CapabilitySet

    ///
    /// Fetch the apps navigation entries the server advertises for the authenticated user.
    ///
    func navigation() async throws -> [NavigationItem]

    ///
    /// List the notifications currently queued for the authenticated user.
    ///
    func notifications() async throws -> [NotificationItem]

    ///
    /// List the Nextcloud Talk conversations the authenticated user takes part in.
    ///
    func conversations() async throws -> [Conversation]

    ///
    /// Retrieve the image of a single Nextcloud Talk conversation.
    ///
    func conversationAvatar(_ token: String, darkTheme: Bool) async throws -> ConversationAvatar

    ///
    /// List the collectives the authenticated user is a member of.
    ///
    func collectives() async throws -> [Collective]

    ///
    /// List the metadata of the pages within a single collective.
    ///
    func pages(inCollective collectiveId: Int) async throws -> [CollectivePage]

    ///
    /// List all notes of the authenticated user.
    ///
    func notes() async throws -> [Note]

    ///
    /// List the notes of the authenticated user which changed since a given moment, together with the identifiers of those which did not.
    ///
    func notes(changedSince: Date) async throws -> NoteChanges

    ///
    /// Look up the settings the notes app keeps for the authenticated user.
    ///
    func notesSettings() async throws -> NotesSettings

    ///
    /// Retrieve one page of the activity stream the server records for the authenticated user.
    ///
    func activities(filter: String, since: Int, limit: Int, sort: ActivitySort, previews: Bool, objectType: String?, objectId: String?) async throws -> ActivityPage

    ///
    /// List the filters the server offers to narrow the activity stream down with.
    ///
    func activityFilters() async throws -> [ActivityFilter]

    ///
    /// Observe server-side changes, preferring the `notify_push` WebSocket when the server advertises it and falling back to polling otherwise.
    ///
    func events(_ options: ServerEventOptions) -> AsyncThrowingStream<ServerEvent, Error>

    ///
    /// Look up the login flow information.
    ///
    func login() async throws -> LoginFlow

    ///
    /// Poll the status of a login flow.
    ///
    func poll(_ endpoint: URL, token: String) async throws -> LoginResult

    ///
    /// Delete the app password this ``Server`` is currently authenticating with, ending the account's session on the server side.
    ///
    func deleteAppPassword() async throws
}
