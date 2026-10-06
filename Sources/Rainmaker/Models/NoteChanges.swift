// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The notes which changed since a given moment, together with the identifiers of those which did not, and what the server said about the response itself.
///
/// This is what ``Server/notes(changedSince:)`` and ``Server/notes(changedSince:ifChangedFrom:)`` return. The server answers such a request with the full content of every note it recorded a change for since the given moment and reduces every other note to its identifier alone, which is why the two arrive separately here. Both together are the complete set of notes the account has, so a note whose identifier appears in neither was deleted on the server.
///
/// The moment to pass on the next call is ``lastModified``, which is the server's own clock rather than the device's. The first synchronization passes `Date.distantPast` instead, which prunes nothing and therefore also yields a ``lastModified`` to continue from:
///
/// ```swift
/// let changes = try await server.notes(changedSince: store.lastModified ?? .distantPast)
///
/// for note in changes.changed {
///     // A note the server could not read is listed like any other, carrying a message about the failure in place of its text. Storing it would replace a perfectly good local copy with that message.
///     guard note.hasError == false else {
///         report(note.errorType, for: note.id)
///         continue
///     }
///
///     store.upsert(note)
/// }
///
/// // Only a complete response lists every note the account has, so deletions are derived from nothing else.
/// guard changes.isComplete else {
///     return
/// }
///
/// // Every identifier the server returned, the unreadable ones included, so a note it could not read this time is not mistaken for one which was deleted.
/// store.deleteAll(exceptFor: changes.changed.map(\.id) + changes.unchanged)
///
/// // Remembered only once everything was applied, so an interrupted synchronization repeats rather than skips what it missed.
/// store.lastModified = changes.lastModified
/// store.entityTag = changes.entityTag
/// ```
///
/// Passing the remembered ``entityTag`` to ``Server/notes(changedSince:ifChangedFrom:)`` along with the remembered ``lastModified`` spares the transfer altogether while nothing changed, because the server then answers with an empty `304 Not Modified`, which that call returns as `nil` and which leaves both remembered values as they are.
///
/// The moment must never come from a note's ``Note/modification`` date, because the server prunes by when it noticed a change rather than by the date of the note: a note may be from 2020, but when the server only found it today it is not pruned. See ``Server/notes(changedSince:)``.
///
/// The server can also split such a response into chunks, each of which but the last carries a ``chunkCursor`` to continue from and the ``pendingCount`` of notes still to come. Only the last chunk lists the identifiers of the notes not sent in full, those sent by the earlier chunks included, which is why ``isComplete`` has to be checked before deriving deletions, and why ``lastModified`` is only worth remembering once the last chunk was applied.
///
public struct NoteChanges: Model, Hashable {
    ///
    /// The notes the server recorded a change for at or after the requested moment, in the order returned by the server.
    ///
    /// Empty whenever nothing changed, which is the common case for a client polling frequently.
    /// This can include a note the server could not read, which is reported through ``Note/hasError`` rather than by leaving it out, so its identifier still counts towards what exists.
    ///
    public let changed: [Note]

    ///
    /// The identifiers of the notes the server recorded no change for and therefore reduced to just those identifiers.
    ///
    /// These carry no content on purpose: a client already has it and only needs to know the note still exists.
    /// When the response is one chunk of several, only the last one, which ``isComplete``, carries these, and then also for the notes the earlier chunks sent in full.
    ///
    public let unchanged: [Int]

    ///
    /// The moment the server started answering, read from the `Last-Modified` header of the response, which is the value to pass as `changedSince` on the next call to ``Server/notes(changedSince:)``.
    ///
    /// This is measured on the server's clock, which is what the server prunes against, so a device whose clock is off can neither miss nor repeat changes by using it.
    /// Every chunk of one chunked retrieval carries the same value, because the server keeps the moment the first chunk was requested in the ``chunkCursor``.
    /// The server only sends whole seconds and keeps every note which changed in the very second it names, so reusing it never skips a change made while the response was being built.
    /// This is `nil` when the header is absent or is not an HTTP date, which the notes app never causes on its own.
    ///
    public let lastModified: Date?

    ///
    /// The entity tag of the response, read from its `ETag` header without the quotes and without a `W/` prefix.
    ///
    /// Pass it to ``Server/notes(changedSince:ifChangedFrom:)`` together with ``lastModified`` to learn without a transfer whether anything changed since.
    /// The server computes it from the body of the response, so it matches a later response exactly when that would have the same body, regardless of the moment it was requested for.
    /// It describes the whole response, unlike ``Note/entityTag``, which describes one note.
    /// This is `nil` when the header is absent.
    ///
    public let entityTag: String?

    ///
    /// The opaque position to continue a chunked retrieval from, read from the `X-Notes-Chunk-Cursor` header of the response.
    ///
    /// This is `nil` for the last chunk and for a response which was not split into chunks at all, which is what ``isComplete`` reports.
    /// Its format is the notes app's business, so it is meant to be handed back as it is rather than to be read.
    ///
    public let chunkCursor: String?

    ///
    /// How many notes the server still has to send in full after this chunk, read from the `X-Notes-Chunk-Pending` header of the response.
    ///
    /// This is `nil` whenever ``chunkCursor`` is, because the server only sends either of them while notes are pending.
    ///
    public let pendingCount: Int?

    ///
    /// Whether this is the last chunk of a retrieval or a response which was not split into chunks at all, which is when ``chunkCursor`` is `nil`.
    ///
    /// Only such a response lists the identifiers of every note the account has, so deletions must only be derived from it and ``lastModified`` should only be remembered after it was applied.
    ///
    public var isComplete: Bool {
        chunkCursor == nil
    }

    ///
    /// Create changes from their individual values, for example to stand in for a server's response in the tests of a downstream project.
    ///
    /// - Parameters:
    ///     - changed: The notes sent in full, see ``changed``.
    ///     - unchanged: The identifiers of the notes sent as identifiers alone, see ``unchanged``.
    ///     - lastModified: The moment to continue from, see ``lastModified``. Defaults to `nil`.
    ///     - entityTag: The entity tag of the response without quotes, see ``entityTag``. Defaults to `nil`.
    ///     - chunkCursor: The position to continue a chunked retrieval from, see ``chunkCursor``. Defaults to `nil`, which makes the changes complete.
    ///     - pendingCount: How many notes are still to come, see ``pendingCount``. Defaults to `nil`.
    ///
    public init(changed: [Note], unchanged: [Int], lastModified: Date? = nil, entityTag: String? = nil, chunkCursor: String? = nil, pendingCount: Int? = nil) {
        self.changed = changed
        self.unchanged = unchanged
        self.lastModified = lastModified
        self.entityTag = entityTag
        self.chunkCursor = chunkCursor
        self.pendingCount = pendingCount
    }

    // MARK: - Encodable

    ///
    /// The keys changes are encoded under, which are the property names.
    ///
    /// ``isComplete`` is not among them, because it is derived from ``chunkCursor`` alone.
    ///
    private enum EncodingKeys: String, CodingKey {
        case changed
        case unchanged
        case lastModified
        case entityTag
        case chunkCursor
        case pendingCount
    }

    ///
    /// Encode changes under their property names.
    ///
    /// Absent values are encoded as `null` rather than left out, so that the encoded form always has the same keys, as with ``NotesSettings``.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(changed, forKey: .changed)
        try container.encode(unchanged, forKey: .unchanged)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(entityTag, forKey: .entityTag)
        try container.encode(chunkCursor, forKey: .chunkCursor)
        try container.encode(pendingCount, forKey: .pendingCount)
    }
}
