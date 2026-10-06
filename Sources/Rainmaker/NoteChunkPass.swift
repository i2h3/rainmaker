// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The state of one chunked pass over the notes which changed since a given moment, which ``Server/noteChunks(changedSince:chunkSize:)`` unfolds its stream from.
///
/// Each call to ``next()`` retrieves one chunk through ``Server/notes(changedSince:chunkSize:continuingAfter:)``, continuing from the ``NoteChanges/chunkCursor`` of the chunk before, until a chunk is ``NoteChanges/isComplete`` or a request fails.
/// It is an actor because the stream's unfolding closure is `@Sendable` while the cursor changes from one chunk to the next.
/// The requests run within the task which awaits ``next()``, which is the task iterating the stream, so cancelling that task cancels the request in flight.
///
actor NoteChunkPass {
    ///
    /// The server the chunks are retrieved from.
    ///
    private let server: Server

    ///
    /// The moment the pass retrieves changes since, which is sent unchanged with every chunk because the server prunes each of them by it.
    ///
    private let changedSince: Date

    ///
    /// The number of notes each chunk sends in full at most, which ``Server/notes(changedSince:chunkSize:continuingAfter:)`` raises to one when smaller.
    ///
    private let chunkSize: Int

    ///
    /// The ``NoteChanges/chunkCursor`` of the chunk retrieved last, which the next chunk continues from, or `nil` before the first chunk.
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
    ///     - server: The server to retrieve the chunks from.
    ///     - changedSince: The moment to retrieve changes since.
    ///     - chunkSize: The number of notes each chunk sends in full at most.
    ///
    init(server: Server, changedSince: Date, chunkSize: Int) {
        self.server = server
        self.changedSince = changedSince
        self.chunkSize = chunkSize
    }

    ///
    /// Retrieve the next chunk of the pass, or `nil` once the pass is over.
    ///
    /// The pass is over after a chunk which ``NoteChanges/isComplete`` and after the first error, which is rethrown, so the stream built on this finishes either way.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled before the request is sent, ``RainmakerError/responseDecodingFailed(reason:)`` when the server answers with the cursor it was asked to continue from, and otherwise whatever ``Server/notes(changedSince:chunkSize:continuingAfter:)`` throws.
    ///
    func next() async throws -> NoteChanges? {
        guard isFinished == false else {
            return nil
        }

        // Ending the pass before any error propagates means no later call can send another request for it.
        isFinished = true
        try Task.checkCancellation()

        let sentCursor = cursor
        let chunk = try await server.notes(changedSince: changedSince, chunkSize: chunkSize, continuingAfter: sentCursor)

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
