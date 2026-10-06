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
    /// Retrieve the avatar of a single Nextcloud user.
    ///
    func userAvatar(_ userId: String, size: AvatarSize, darkTheme: Bool) async throws -> UserAvatar

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
    /// List the notes of the authenticated user which changed since a given moment, unless the answer would be the same as the one a given entity tag was taken from.
    ///
    func notes(changedSince: Date, ifChangedFrom entityTag: String) async throws -> NoteChanges?

    ///
    /// Retrieve one chunk of the notes of the authenticated user which changed since a given moment, either the first one of a pass or the one following a given cursor.
    ///
    func notes(changedSince: Date, chunkSize: Int, continuingAfter cursor: String?) async throws -> NoteChanges

    ///
    /// Retrieve the first chunk of the notes of the authenticated user which changed since a given moment, unless the answer would be the same as the one a given entity tag was taken from.
    ///
    func notes(changedSince: Date, chunkSize: Int, ifChangedFrom entityTag: String) async throws -> NoteChanges?

    ///
    /// Retrieve every chunk of one pass over the notes of the authenticated user which changed since a given moment, in order, as a stream.
    ///
    func noteChunks(changedSince: Date, chunkSize: Int) -> AsyncThrowingStream<NoteChanges, Error>

    ///
    /// List the notes of the authenticated user which changed since a given moment without their text, together with the identifiers of those which did not.
    ///
    func noteSummaries(changedSince: Date) async throws -> NoteSummaryChanges

    ///
    /// List the notes of the authenticated user which changed since a given moment without their text, unless the answer would be the same as the one a given entity tag was taken from.
    ///
    func noteSummaries(changedSince: Date, ifChangedFrom entityTag: String) async throws -> NoteSummaryChanges?

    ///
    /// Retrieve one chunk of the notes of the authenticated user which changed since a given moment without their text, either the first one of a pass or the one following a given cursor.
    ///
    func noteSummaries(changedSince: Date, chunkSize: Int, continuingAfter cursor: String?) async throws -> NoteSummaryChanges

    ///
    /// Retrieve the first chunk of the notes of the authenticated user which changed since a given moment without their text, unless the answer would be the same as the one a given entity tag was taken from.
    ///
    func noteSummaries(changedSince: Date, chunkSize: Int, ifChangedFrom entityTag: String) async throws -> NoteSummaryChanges?

    ///
    /// Retrieve every chunk of one pass over the notes of the authenticated user which changed since a given moment without their text, in order, as a stream.
    ///
    func noteSummaryChunks(changedSince: Date, chunkSize: Int) -> AsyncThrowingStream<NoteSummaryChanges, Error>

    ///
    /// Retrieve a single note of the authenticated user by its identifier.
    ///
    func note(_ id: Int) async throws -> Note

    ///
    /// Retrieve a single note of the authenticated user by its identifier, unless it is still the one a given entity tag was taken from.
    ///
    func note(_ id: Int, ifChangedFrom entityTag: String) async throws -> Note?

    ///
    /// Create a note for the authenticated user and return it as the server stored it.
    ///
    func createNote(title: String, category: String, content: String, modification: Date?, isFavorite: Bool) async throws -> Note

    ///
    /// Change a note of the authenticated user and return it as the server stored it, optionally only if it is still the one a given entity tag was taken from.
    ///
    func updateNote(_ id: Int, title: String?, category: String?, content: String?, modification: Date?, isFavorite: Bool?, ifMatching entityTag: String?) async throws -> Note

    ///
    /// Delete a note of the authenticated user.
    ///
    func deleteNote(_ id: Int) async throws

    ///
    /// Retrieve a file a note refers to, such as an image embedded into it, into memory.
    ///
    func attachment(at path: String, ofNote noteId: Int) async throws -> NoteAttachment

    ///
    /// Retrieve a file a note refers to, such as an image embedded into it, into a local file.
    ///
    func downloadAttachment(at path: String, ofNote noteId: Int, to destination: URL, force: Bool) async throws -> NoteAttachmentFile

    ///
    /// Attach a local file to a note of the authenticated user and return the path the server stored it at.
    ///
    func addAttachment(_ source: URL, toNote noteId: Int, fileName: String?) async throws -> String

    ///
    /// Attach the given bytes as a file to a note of the authenticated user and return the path the server stored it at.
    ///
    func addAttachment(_ data: Data, toNote noteId: Int, fileName: String) async throws -> String

    ///
    /// Delete a file attached to a note of the authenticated user.
    ///
    func deleteAttachment(at path: String, ofNote noteId: Int) async throws

    ///
    /// Look up the settings the notes app keeps for the authenticated user.
    ///
    func notesSettings() async throws -> NotesSettings

    ///
    /// Change the settings the notes app keeps for the authenticated user and return them as the server stored them.
    ///
    func updateNotesSettings(notesPath: String?, fileSuffix: String?, noteMode: NoteMode?, showsHiddenFiles: Bool?, loadsRecentNoteOnStartUp: Bool?) async throws -> NotesSettings

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
