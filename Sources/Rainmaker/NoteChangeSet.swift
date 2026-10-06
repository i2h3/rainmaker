// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What ``NoteChanges`` and ``NoteSummaryChanges`` have in common, which is what lets the listings of notes with and without their content share one implementation of their requests, of reading a response into a result and of a chunked pass.
///
/// The two listings differ in nothing but whether the request leaves out the content of the notes it sends in full, which ``excludesContent`` says, and in the type those notes are decoded as, which ``Item`` names.
/// `Server.makeNoteChanges(from:response:)` reads a response into any conforming type and ``NoteChunkPass`` unfolds a stream of chunks of any of them, so the public listings stay concrete and documented one by one while their logic exists only once.
/// It is internal on purpose: a downstream project only ever sees the two concrete types, which conform to it through `Extensions/NoteChanges+NoteChangeSet.swift` and `Extensions/NoteSummaryChanges+NoteChangeSet.swift`.
///
protocol NoteChangeSet: Sendable {
    ///
    /// The type a note sent in full is decoded as, which is ``Note`` for ``NoteChanges`` and ``NoteSummary`` for ``NoteSummaryChanges``.
    ///
    associatedtype Item: Decodable

    ///
    /// Whether the request for this kind of listing asks the server to leave out the content of the notes it sends in full, which is sent as the `exclude` parameter by `Server.makeNoteChangesRequest(changedSince:excludesContent:chunkSize:chunkCursor:headerFields:)`.
    ///
    /// It is a property of the result type rather than an argument of each call, so that a listing whose notes are decoded as ``Note`` can never ask for notes without the content ``Note`` requires.
    ///
    static var excludesContent: Bool { get }

    ///
    /// The opaque position to continue a chunked retrieval from, which ``NoteChunkPass`` hands to the next request, or `nil` for the last chunk.
    ///
    var chunkCursor: String? { get }

    ///
    /// Create a listing from the notes the server sent in full, the identifiers of those it did not, and what the headers of the response said.
    ///
    /// - Parameters:
    ///     - changed: The notes sent in full.
    ///     - unchanged: The identifiers of the notes sent as identifiers alone.
    ///     - lastModified: The moment read from the `Last-Modified` header.
    ///     - entityTag: The entity tag read from the `ETag` header, without quotes.
    ///     - chunkCursor: The cursor read from the `X-Notes-Chunk-Cursor` header.
    ///     - pendingCount: The number read from the `X-Notes-Chunk-Pending` header.
    ///
    init(changed: [Item], unchanged: [Int], lastModified: Date?, entityTag: String?, chunkCursor: String?, pendingCount: Int?)
}
