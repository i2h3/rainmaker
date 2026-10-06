// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The summaries of the notes which changed since a given moment, together with the identifiers of those which did not, and what the server said about the response itself.
///
/// This is to ``NoteChanges`` what ``NoteSummary`` is to ``Note``: the result of the listings which ask the server to leave out the text of every note, ``Server/noteSummaries(changedSince:)`` and ``Server/noteSummaries(changedSince:ifChangedFrom:)``, and what each chunk of ``Server/noteSummaries(changedSince:chunkSize:continuingAfter:)``, ``Server/noteSummaries(changedSince:chunkSize:ifChangedFrom:)`` and ``Server/noteSummaryChunks(changedSince:chunkSize:)`` is.
/// Everything ``NoteChanges`` says about how the two halves are applied, about which moment to continue from and about chunks holds for this type as well, because the server answers both kinds of listing alike but for the text it leaves out.
///
/// ```swift
/// let changes = try await server.noteSummaries(changedSince: store.lastModified ?? .distantPast)
///
/// // A summary carries no error, because the server only notices one while reading a note's text, so every summary is stored as it is.
/// store.upsert(changes.changed)
///
/// // Only a complete response lists every note the account has, so deletions are derived from nothing else.
/// guard changes.isComplete else {
///     return
/// }
///
/// store.deleteAll(exceptFor: changes.changed.map(\.id) + changes.unchanged)
///
/// // Remembered only once everything was applied, so an interrupted synchronization repeats rather than skips what it missed.
/// store.lastModified = changes.lastModified
/// store.entityTag = changes.entityTag
/// ```
///
/// A note whose text alone changed is among the ``changed`` summaries as well, with a new ``NoteSummary/entityTag``, because the server's record of when it last saw a note change covers the text even though the text is not sent.
///
/// The ``entityTag`` describes a response without any text, so it only matches a later response of a summary listing. Pass it to ``Server/noteSummaries(changedSince:ifChangedFrom:)`` rather than to ``Server/notes(changedSince:ifChangedFrom:)``, where it would only match while neither response sends a note in full.
///
public struct NoteSummaryChanges: Model, Hashable {
    ///
    /// The summaries of the notes the server recorded a change for at or after the requested moment, in the order returned by the server.
    ///
    /// Empty whenever nothing changed, which is the common case for a client polling frequently.
    /// Unlike ``NoteChanges/changed`` this never reports a note the server could not read, because the server does not try to read any note's text for such a listing, see ``NoteSummary``.
    ///
    public let changed: [NoteSummary]

    ///
    /// The identifiers of the notes the server recorded no change for and therefore reduced to just those identifiers.
    ///
    /// When the response is one chunk of several, only the last one, which ``isComplete``, carries these, and then also for the notes the earlier chunks sent in full, as with ``NoteChanges/unchanged``.
    ///
    public let unchanged: [Int]

    ///
    /// The moment the server started answering, read from the `Last-Modified` header of the response, which is the value to pass as `changedSince` on the next call to ``Server/noteSummaries(changedSince:)``.
    ///
    /// It means exactly what ``NoteChanges/lastModified`` means, and it is `nil` when the header is absent or is not an HTTP date.
    ///
    public let lastModified: Date?

    ///
    /// The entity tag of the response, read from its `ETag` header without the quotes and without a `W/` prefix.
    ///
    /// Pass it to ``Server/noteSummaries(changedSince:ifChangedFrom:)`` together with ``lastModified`` to learn without a transfer whether anything changed since.
    /// The server computes it from the body of the response, which for a summary listing holds no text, so it differs from the ``NoteChanges/entityTag`` of a listing with text whenever a note is sent in full.
    /// It describes the whole response, unlike ``NoteSummary/entityTag``, which describes one note.
    /// This is `nil` when the header is absent.
    ///
    public let entityTag: String?

    ///
    /// The opaque position to continue a chunked retrieval from, read from the `X-Notes-Chunk-Cursor` header of the response, which ``Server/noteSummaries(changedSince:chunkSize:continuingAfter:)`` takes to retrieve the next chunk.
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
    ///     - changed: The summaries of the notes sent in full, see ``changed``.
    ///     - unchanged: The identifiers of the notes sent as identifiers alone, see ``unchanged``.
    ///     - lastModified: The moment to continue from, see ``lastModified``. Defaults to `nil`.
    ///     - entityTag: The entity tag of the response without quotes, see ``entityTag``. Defaults to `nil`.
    ///     - chunkCursor: The position to continue a chunked retrieval from, see ``chunkCursor``. Defaults to `nil`, which makes the changes complete.
    ///     - pendingCount: How many notes are still to come, see ``pendingCount``. Defaults to `nil`.
    ///
    public init(changed: [NoteSummary], unchanged: [Int], lastModified: Date? = nil, entityTag: String? = nil, chunkCursor: String? = nil, pendingCount: Int? = nil) {
        self.changed = changed
        self.unchanged = unchanged
        self.lastModified = lastModified
        self.entityTag = entityTag
        self.chunkCursor = chunkCursor
        self.pendingCount = pendingCount
    }

    // MARK: - Encodable

    ///
    /// The keys changes are encoded under, which are the property names, the same as those of ``NoteChanges``.
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
    /// Absent values are encoded as `null` rather than left out, so that the encoded form always has the same keys, as with ``NoteChanges``.
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
