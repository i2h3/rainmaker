// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The state of one chunked pass over the notes which changed since a given moment, which ``Server/noteChunks(changedSince:chunkSize:)`` and ``Server/noteSummaryChunks(changedSince:chunkSize:)`` unfold their streams from.
///
/// Each call to ``next()`` retrieves one chunk through the closure the pass was created with, which is ``Server/notes(changedSince:chunkSize:continuingAfter:)`` or ``Server/noteSummaries(changedSince:chunkSize:continuingAfter:)`` with the moment and the chunk size of the pass, continuing from the ``NoteChangeSet/chunkCursor`` of the chunk before, until a chunk has no cursor or a request fails.
/// It is generic over the ``NoteChangeSet`` a chunk is, so that both streams share the same rules for when a pass is over.
/// It is an actor because the stream's unfolding closure is `@Sendable` while the cursor changes from one chunk to the next.
/// The requests run within the task which awaits ``next()``, which is the task iterating the stream, so cancelling that task cancels the request in flight.
///
actor NoteChunkPass<Changes: NoteChangeSet> {
    ///
    /// Retrieve the chunk following the given cursor, or the first chunk of the pass for `nil`, always with the moment and the chunk size the pass was started with, because the server prunes each chunk by that moment.
    ///
    private let retrieve: @Sendable (_ cursor: String?) async throws -> Changes

    ///
    /// The ``NoteChangeSet/chunkCursor`` of the chunk retrieved last, which the next chunk continues from, or `nil` before the first chunk.
    ///
    private var cursor: String?

    ///
    /// Whether the pass is over, because the last chunk was retrieved or a request failed, after which ``next()`` sends no further request.
    ///
    private var isFinished = false

    ///
    /// Create a pass which has not retrieved any chunk yet.
    ///
    /// - Parameters:
    ///     - retrieve: Retrieve the chunk following the given cursor, or the first chunk for `nil`, with the moment and the chunk size of the pass.
    ///
    init(retrieve: @escaping @Sendable (_ cursor: String?) async throws -> Changes) {
        self.retrieve = retrieve
    }

    ///
    /// Retrieve the next chunk of the pass, or `nil` once the pass is over.
    ///
    /// The pass is over after a chunk without a ``NoteChangeSet/chunkCursor``, which is the complete one, and after the first error, which is rethrown, so the stream built on this finishes either way.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled before the request is sent, ``RainmakerError/responseDecodingFailed(reason:)`` when the server answers with the cursor it was asked to continue from, and otherwise whatever ``retrieve`` throws.
    ///
    func next() async throws -> Changes? {
        guard isFinished == false else {
            return nil
        }

        // Ending the pass before any error propagates means no later call can send another request for it.
        isFinished = true
        try Task.checkCancellation()

        let sentCursor = cursor
        let chunk = try await retrieve(sentCursor)

        guard let nextCursor = chunk.chunkCursor else {
            return chunk
        }

        // The server orders the notes it sends and every cursor points past the last note of its chunk, so a cursor which does not advance means the server ignores it and would answer with the same chunk forever.
        guard nextCursor != sentCursor else {
            throw RainmakerError.responseDecodingFailed(reason: "The server answered a chunk of notes with the cursor it was asked to continue from.")
        }

        cursor = nextCursor
        isFinished = false

        return chunk
    }
}
