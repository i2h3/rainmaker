// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

public extension Server {
    ///
    /// List all notes of the authenticated user.
    ///
    /// Notes are provided by the server's notes app which, unlike most of what this library covers, is not part of a Nextcloud installation and has to be installed separately. Whether it is available can be checked in advance via the ``Notes`` capability, e.g. `try await capabilities().contains(Notes.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/appUnavailable(app:)`` for `"notes"`.
    ///
    /// The very same error is what a server causes whose `index.php` routing is disabled or whose reverse proxy swallows the route, so those causes cannot be told apart from the response alone. It is deliberately not ``RainmakerError/notFound``, which the notes features reserve for a note that does not exist, so that a client keeping its own copy never takes a missing app for an account without notes.
    ///
    /// An app which is installed but older than ``Notes/minimumAPIVersion`` is reported separately, as ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``. That requirement is checked on every response, because the notes API advertises the versions it serves in a header of its own, and it can be checked in advance through ``Notes/isSupported``.
    ///
    /// The whole collection is retrieved in a single request, because the endpoint returns everything at once unless a chunk size is requested, which this deliberately does not do. Use ``notes(changedSince:)`` to retrieve only what changed since an earlier call, and ``noteChunks(changedSince:chunkSize:)`` to retrieve it in chunks of a bounded size.
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
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes() async throws -> [Note] {
        try requireCredentials()
        logger.debug("Fetching notes...")

        let request = try makeNotesAPIRequest(for: "notes", method: .get)
        let (data, _) = try await notesAPIResponse(for: request)

        return try decodeNotesAPIPayload([Note].self, from: data, describing: "the notes")
    }

    ///
    /// List the notes of the authenticated user which changed since a given moment, together with the identifiers of those which did not.
    ///
    /// This is the incremental counterpart of ``notes()`` for a client keeping its own copy of the notes: the server returns every note it recorded a change for at or after `changedSince` in full, and reduces every note it did not to its identifier alone. Both together are the complete set of notes the account has, which is what makes deletions detectable. See ``NoteChanges`` for how the two halves are meant to be applied.
    ///
    /// The moment is sent to the server as its `pruneBefore` parameter, converted to whole seconds since the Unix epoch. A moment at or before the epoch, such as `Date.distantPast`, prunes nothing and therefore returns every note in full, which is how a first synchronization starts.
    ///
    /// Along with the notes, the result carries what the server says about the response in its headers: ``NoteChanges/lastModified`` is the moment to pass on the next call, and ``NoteChanges/entityTag`` is what ``notes(changedSince:ifChangedFrom:)`` takes to skip the transfer while nothing changed. The whole collection is retrieved in a single response, so the result is always ``NoteChanges/isComplete``. A client which must not hold every changed note at once retrieves them in chunks through ``notes(changedSince:chunkSize:continuingAfter:)`` or ``noteChunks(changedSince:chunkSize:)`` instead.
    ///
    /// > Warning: The server compares this moment against its own record of when it last noticed each note change, which is not the same as that note's ``Note/modification`` date. A note may be from 2020, but when the server only found it today it is not pruned from the response. Never pass a note's ``Note/modification`` back in as this moment; pass the ``NoteChanges/lastModified`` of the previous call, which is the server's own time at which it started answering, and which the API defines as the value to reuse.
    ///
    /// Everything else, including how an unavailable app surfaces and how a note the server could not read is reported, matches ``notes()``.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, usually the ``NoteChanges/lastModified`` of the previous call, and measured against the server's own record of when it last saw a note change rather than against ``Note/modification``.
    ///
    /// - Returns: The changed notes, the identifiers of the unchanged ones and what the response headers say about them.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes(changedSince: Date) async throws -> NoteChanges {
        try requireCredentials()
        logger.debug("Fetching notes changed since \(changedSince)...")

        let request = try makeNoteChangesRequest(changedSince: changedSince)
        let (data, response) = try await notesAPIResponse(for: request)

        return try makeNoteChanges(from: data, response: response)
    }

    ///
    /// List the notes of the authenticated user which changed since a given moment like ``notes(changedSince:)``, unless the answer would be the same as the one a given entity tag was taken from.
    ///
    /// The request carries the entity tag in its `If-None-Match` header. When the server would answer exactly what it answered when it handed out that tag, it responds with an empty `304 Not Modified` instead, which this returns as `nil`. That spares a frequently polling client the transfer of the identifiers of every note while nothing changed.
    ///
    /// Pass the ``NoteChanges/entityTag`` and the ``NoteChanges/lastModified`` of the previous result. The server computes the tag from the body it would send rather than from the moment, so the tag matches whenever the body would be the same, which is the case while no note changed, none was added and none was deleted. The first call after a result carrying notes in full still receives a complete response, because it now reduces those notes to their identifiers, while every further call answers `nil` until something changes. A tag which does not match simply results in a complete response as ``notes(changedSince:)`` would return it. A tag with or without quotes and with a `W/` prefix is accepted alike.
    ///
    /// `nil` deliberately differs from an empty ``NoteChanges``, which would claim that the account has no notes at all and make a client keeping its own copy delete them. On `nil`, keep the previous `changedSince` and entity tag for the next call. That never skips a change, because the server keeps every note which changed in the very second the moment names.
    ///
    /// The same requirement and the same failure modes as ``notes(changedSince:)`` apply.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, usually the ``NoteChanges/lastModified`` of the previous result.
    ///     - entityTag: The ``NoteChanges/entityTag`` of the previous result.
    ///
    /// - Returns: The changed notes, the identifiers of the unchanged ones and what the response headers say about them, or `nil` when the server answered that nothing changed.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes(changedSince: Date, ifChangedFrom entityTag: String) async throws -> NoteChanges? {
        try requireCredentials()
        logger.debug("Fetching notes changed since \(changedSince) unless unchanged...")

        // The server only recognizes the tag when the header repeats it quoted and exactly as it computed it, so a weakness marker a proxy may have added is dropped before quoting.
        let request = try makeNoteChangesRequest(changedSince: changedSince, headerFields: ["If-None-Match": entityTag.unquotedEntityTag.quotedEntityTag])
        let (data, response) = try await notesAPIResponse(for: request, allowsNotModified: true)

        guard response.status != .notModified else {
            logger.debug("Notes did not change.")
            return nil
        }

        return try makeNoteChanges(from: data, response: response)
    }

    ///
    /// Retrieve one chunk of the notes of the authenticated user which changed since a given moment, either the first one of a pass or the one following a given cursor.
    ///
    /// This is the chunked counterpart of ``notes(changedSince:)`` for a client which must not hold every changed note at once, such as an extension or a watch app with little memory to spare. The server orders the notes it would send in full by when it last saw each of them change and sends at most `chunkSize` of them per response. Every chunk but the last carries a ``NoteChanges/chunkCursor`` to pass as `cursor` for the next one, along with the ``NoteChanges/pendingCount`` of notes still to come, and lists no identifiers in ``NoteChanges/unchanged``.
    ///
    /// The last chunk, which ``NoteChanges/isComplete``, is the only one which lists the identifiers of the other notes the account has, and it lists those the earlier chunks sent in full as well. Deletions must therefore only be derived from the last chunk, from its ``NoteChanges/changed`` and ``NoteChanges/unchanged`` alone, and never from what a pass collected along the way.
    ///
    /// Every chunk of one pass carries the same ``NoteChanges/lastModified``, because the cursor keeps the moment the server started answering the first chunk. Remember it only once the last chunk was applied, so that an interrupted pass is repeated rather than skipped.
    ///
    /// A cursor is a plain value meant to be handed back as it is. That is what lets a pass which was interrupted, for example because the system suspended the app, continue later from the cursor of the last chunk applied rather than start over, provided `changedSince` is the same as for the chunks before. A cursor the server cannot read makes it start a new pass with the first chunk instead.
    ///
    /// ``noteChunks(changedSince:chunkSize:)`` performs a whole pass with this call, as a stream of chunks.
    ///
    /// The server also offers to narrow a listing down to one category, which this deliberately never asks for: that filter narrows the identifiers of the last chunk as well, which would make every note outside the category look deleted.
    ///
    /// Everything else, including how `changedSince` is measured, how an unavailable app surfaces and how a note the server could not read is reported, matches ``notes(changedSince:)``.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, usually the ``NoteChanges/lastModified`` of the previous pass, and the same for every chunk of one pass.
    ///     - chunkSize: The number of notes to send in full at most, which is raised to one when smaller, because the server takes zero as a request not to split the response at all.
    ///     - cursor: The ``NoteChanges/chunkCursor`` of the previous chunk of the same pass, or `nil` to retrieve the first chunk of a new pass. Defaults to `nil`.
    ///
    /// - Returns: The notes of this chunk, the identifiers of the unchanged notes when it is the last chunk, and what the response headers say about them.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes(changedSince: Date, chunkSize: Int, continuingAfter cursor: String? = nil) async throws -> NoteChanges {
        try requireCredentials()
        logger.debug("Fetching a chunk of notes changed since \(changedSince)...")

        let request = try makeNoteChangesRequest(changedSince: changedSince, chunkSize: chunkSize, chunkCursor: cursor)
        let (data, response) = try await notesAPIResponse(for: request)

        return try makeNoteChanges(from: data, response: response)
    }

    ///
    /// Retrieve the first chunk of the notes of the authenticated user which changed since a given moment like ``notes(changedSince:chunkSize:continuingAfter:)``, unless the answer would be the same as the one a given entity tag was taken from.
    ///
    /// This is to a chunked pass what ``notes(changedSince:ifChangedFrom:)`` is to a single response: the request carries the entity tag in its `If-None-Match` header, and the server answers with an empty `304 Not Modified` instead of the chunk when it would send exactly what it sent when it handed out that tag, which this returns as `nil`.
    ///
    /// Pass the ``NoteChanges/entityTag`` and the ``NoteChanges/lastModified`` of the last chunk of the previous pass. While no note changed, the first chunk sends no note in full and therefore already is the last one, listing nothing but identifiers, so its tag does not depend on the chunk size and matches that of a response to ``notes(changedSince:)`` as well. As with the single response, the first call after a pass which sent notes in full still receives a complete chunk, while every further call answers `nil` until something changes. When a chunk arrives which is not the last one, continue the pass with ``notes(changedSince:chunkSize:continuingAfter:)``.
    ///
    /// There is no conditional variant for the chunks after the first, because each of them is only requested when the first one announced that changes are pending.
    ///
    /// `nil` deliberately differs from an empty ``NoteChanges`` for the reasons ``notes(changedSince:ifChangedFrom:)`` gives. On `nil`, keep the previous `changedSince` and entity tag for the next call.
    ///
    /// The same requirement and the same failure modes as ``notes(changedSince:chunkSize:continuingAfter:)`` apply.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, usually the ``NoteChanges/lastModified`` of the previous pass.
    ///     - chunkSize: The number of notes to send in full at most, which is raised to one when smaller.
    ///     - entityTag: The ``NoteChanges/entityTag`` of the last chunk of the previous pass.
    ///
    /// - Returns: The first chunk of a new pass, or `nil` when the server answered that nothing changed.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes(changedSince: Date, chunkSize: Int, ifChangedFrom entityTag: String) async throws -> NoteChanges? {
        try requireCredentials()
        logger.debug("Fetching the first chunk of notes changed since \(changedSince) unless unchanged...")

        let request = try makeNoteChangesRequest(changedSince: changedSince, chunkSize: chunkSize, headerFields: ["If-None-Match": entityTag.unquotedEntityTag.quotedEntityTag])
        let (data, response) = try await notesAPIResponse(for: request, allowsNotModified: true)

        guard response.status != .notModified else {
            logger.debug("Notes did not change.")
            return nil
        }

        return try makeNoteChanges(from: data, response: response)
    }

    ///
    /// Retrieve every chunk of one pass over the notes of the authenticated user which changed since a given moment, in order, as a stream.
    ///
    /// Each element is the result of one call to ``notes(changedSince:chunkSize:continuingAfter:)``, the first without a cursor and every further one with the ``NoteChanges/chunkCursor`` of the element before. The stream finishes after the element which ``NoteChanges/isComplete``, which is the only one deletions may be derived from and after which ``NoteChanges/lastModified`` is worth remembering, see there.
    ///
    /// A chunk is only requested when the consumer asks for the next element, so the stream never holds more than the chunk being retrieved. A consumer which applies each chunk before it continues therefore needs no more memory for a pass than for one chunk, which is the point of retrieving notes in chunks. Merging the chunks is deliberately left to the consumer, because a merged result would hold every note at once and would no longer tell which identifiers came with the last chunk.
    ///
    /// When the consumer stops iterating, no further chunk is requested. Cancelling the task which iterates cancels the request in flight, which finishes the stream by throwing the error the cancelled request throws, such as `URLError.cancelled`, while a cancellation between two chunks ends the stream without requesting another one. Either way the last chunk received is not complete, which is why a consumer checks ``NoteChanges/isComplete`` rather than assume that a stream which ended was a whole pass.
    ///
    /// The stream finishes by throwing the first error a request throws, with the same failure modes as ``notes(changedSince:chunkSize:continuingAfter:)``, including ``RainmakerError/credentialsRequired`` before anything is sent when no credentials are set. The chunks received until then remain valid, and the cursor of the last one continues the pass through ``notes(changedSince:chunkSize:continuingAfter:)``. A server which answers a chunk with the very cursor it was asked to continue from would repeat that chunk forever, so the stream finishes by throwing ``RainmakerError/responseDecodingFailed(reason:)`` instead.
    ///
    /// ```swift
    /// var lastChunk: NoteChanges?
    ///
    /// for try await chunk in server.noteChunks(changedSince: store.lastModified ?? .distantPast, chunkSize: 50) {
    ///     // Each chunk is applied as it arrives, so it can be released before the next one is requested.
    ///     store.upsert(chunk.changed.filter { $0.hasError == false })
    ///     lastChunk = chunk
    /// }
    ///
    /// // Only the last chunk lists every note the account has, so deletions are derived from it alone.
    /// guard let lastChunk, lastChunk.isComplete else {
    ///     return
    /// }
    ///
    /// store.deleteAll(exceptFor: lastChunk.changed.map(\.id) + lastChunk.unchanged)
    /// store.lastModified = lastChunk.lastModified
    /// store.entityTag = lastChunk.entityTag
    /// ```
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, usually the ``NoteChanges/lastModified`` of the previous pass.
    ///     - chunkSize: The number of notes to send in full at most per chunk, which is raised to one when smaller.
    ///
    /// - Returns: A stream of the chunks of one pass, the last of which is complete.
    ///
    func noteChunks(changedSince: Date, chunkSize: Int) -> AsyncThrowingStream<NoteChanges, Error> {
        logger.debug("Starting a chunked pass over notes changed since \(changedSince)...")

        let pass = NoteChunkPass(server: self, changedSince: changedSince, chunkSize: chunkSize)

        // Unfolding rather than producing from a task of its own makes each request wait until the consumer asks for the next chunk and run within the consumer's task, which is what bounds the memory to one chunk and lets cancelling that task cancel the request.
        return AsyncThrowingStream {
            try await pass.next()
        }
    }

    ///
    /// Retrieve a single note of the authenticated user by its identifier.
    ///
    /// This is what a client asks for when it needs one note as the server has it now, for example to refresh the note being opened, to look at a note it learned the identifier of through ``notes(changedSince:)``, or to perform a single lookup from a Shortcuts action, without listing every note first. The result is the same ``Note`` a listing reports for it, including its ``Note/entityTag``, which ``note(_:ifChangedFrom:)`` takes to skip the transfer while the note did not change.
    ///
    /// A note which does not exist is reported as ``RainmakerError/notFound``. The notes app answers that not only for an identifier which was never assigned or whose note was deleted, but also for one which belongs to a file outside the notes folder or to a file which is not a note, so this cannot be used to reach arbitrary files by their identifier. An absent notes app is reported as ``RainmakerError/appUnavailable(app:)`` instead, as with ``notes()``, so a client keeping its own copy can tell a deleted note from an app which went away.
    ///
    /// A note the server could not read is returned like any other rather than failing the call. It carries ``Note/hasError`` and its ``Note/content`` is a message about the failure rather than the note's text, so anything which stores what it retrieves has to check that first.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - id: The ``Note/id`` of the note to retrieve.
    ///
    /// - Returns: The note as the server has it now.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the account has no note with this identifier.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a note.
    ///     - Any other error that might occur during retrieval.
    ///
    func note(_ id: Int) async throws -> Note {
        try requireCredentials()
        logger.debug("Fetching note \(id)...")

        let request = try makeNotesAPIRequest(for: "notes/\(id)", method: .get)
        let (data, _) = try await notesAPIResponse(for: request)

        return try decodeNotesAPIPayload(Note.self, from: data, describing: "the note")
    }

    ///
    /// Retrieve a single note of the authenticated user by its identifier like ``note(_:)``, unless it is still the one a given entity tag was taken from.
    ///
    /// The request carries the entity tag in its `If-None-Match` header. While the note is unchanged on the server, the server answers with an empty `304 Not Modified` instead of the note, which this returns as `nil`. That spares a client which checks whether its local copy of a note is stale the transfer of the note's whole content.
    ///
    /// Pass the ``Note/entityTag`` of the copy at hand, as a listing, ``note(_:)`` or a previous call of this method reported it. The server derives the tag from the note's ``Note/title``, ``Note/category``, ``Note/content``, ``Note/modification``, ``Note/isFavorite`` and ``Note/isReadOnly``, so `nil` means that none of these changed, while a change of anything else, such as the shares reported in ``Note/shareTypes``, goes unnoticed until one of them changes as well. A tag which does not match simply results in the note as ``note(_:)`` would return it. A tag with or without quotes and with a `W/` prefix is accepted alike.
    ///
    /// A note which no longer exists is reported as ``RainmakerError/notFound`` whatever the tag, so `nil` never hides a deletion.
    ///
    /// The same requirement and the same failure modes as ``note(_:)`` apply.
    ///
    /// - Parameters:
    ///     - id: The ``Note/id`` of the note to retrieve.
    ///     - entityTag: The ``Note/entityTag`` of the copy at hand.
    ///
    /// - Returns: The note as the server has it now, or `nil` when the server answered that it did not change.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the account has no note with this identifier.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a note.
    ///     - Any other error that might occur during retrieval.
    ///
    func note(_ id: Int, ifChangedFrom entityTag: String) async throws -> Note? {
        try requireCredentials()
        logger.debug("Fetching note \(id) unless unchanged...")

        // The server only recognizes the tag when the header repeats it quoted and exactly as it computed it, so a weakness marker a proxy may have added is dropped before quoting.
        let request = try makeNotesAPIRequest(for: "notes/\(id)", method: .get, headerFields: ["If-None-Match": entityTag.unquotedEntityTag.quotedEntityTag])
        let (data, response) = try await notesAPIResponse(for: request, allowsNotModified: true)

        guard response.status != .notModified else {
            logger.debug("Note \(id) did not change.")
            return nil
        }

        return try decodeNotesAPIPayload(Note.self, from: data, describing: "the note")
    }

    ///
    /// Create a note for the authenticated user and return it as the server stored it.
    ///
    /// The server creates the note's file in the account's notes folder, see ``NotesSettings/notesPath``, below the folder `category` names, and returns the new note with the ``Note/id`` and ``Note/entityTag`` it assigned. This is a standalone call which needs nothing but credentials, so it suits a single action such as one of Shortcuts as well as a client keeping its own copy of the notes.
    ///
    /// The title and the category become a file name and a folder, so the server sanitizes both, and a caller has to adopt the ``Note/title``, ``Note/category`` and ``Note/path`` of the result rather than assume what it asked for:
    ///
    /// - Characters which are illegal in file names on some systems, which are `*`, `|`, `/`, `\`, `:`, `"`, `<`, `>` and `?`, are removed from the title, as are leading dots and white space, so that the file is neither hidden nor placed elsewhere.
    /// - Only the first line of the title is kept, any other white space becomes a plain space, and the title is cut off after 100 characters.
    /// - A title which ends up empty becomes the notes app's default title, "New note" localized to the account's language.
    /// - When the category already holds a note of that title, the server appends a number such as `" (2)"` rather than overwrite it.
    /// - Each component of the category, which `/` delimits, is sanitized like the title and empty components are dropped, and the folders it names are created as needed.
    ///
    /// The title is never derived from the content, which only an outdated version of the notes API did. To give a note the title the notes app's web interface would derive from its text, pass what ``NoteTitle/derive(fromContent:)`` returns as `title`, and to learn beforehand which title and category the server will settle on, see ``NoteTitle/sanitize(_:)`` and ``NoteCategory/sanitize(_:)``.
    ///
    /// When `modification` is given, the server stamps it onto the note's file after writing the content, so it becomes ``Note/modification``, which is how a client creating a note it wrote offline keeps the moment it was actually written. Without it, or for a moment at or before the Unix epoch, the note is stamped with the moment the server wrote it.
    ///
    /// > Important: Creating a note is not idempotent. Every call which reaches the server creates another note, even with the same title, which the server then numbers as described above. A call whose response was lost, for example because the connection dropped or because the calling task was cancelled after the request had been sent, may therefore have created a note all the same, and simply repeating it may create a duplicate. Before retrying, list the notes, for example through ``notes(changedSince:)``, and look for the note the first attempt may have created.
    ///
    /// When the server creates the file but then fails to write the content or the other values, it deletes the new note again before it answers with the error, so a call which fails with a response leaves no half created note behind.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - title: The title of the new note, which the server sanitizes as described above.
    ///     - category: The category to file the new note under, with `/` delimiting sub-categories, or an empty string for none. Defaults to an empty string.
    ///     - content: The text of the new note. Defaults to an empty string.
    ///     - modification: The moment to stamp the new note with as its ``Note/modification``, or `nil` to have the server stamp it with the moment it wrote it. It is sent in whole seconds since the Unix epoch. Defaults to `nil`.
    ///     - isFavorite: Whether the new note is marked as a favorite. Defaults to `false`.
    ///
    /// - Returns: The new note as the server stored it, including the sanitized title and category and the identifier and entity tag it assigned.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/insufficientStorage`` when the account's quota leaves no room for the new note.
    ///     - ``RainmakerError/locked`` when a file the server has to write is locked, after the server already retried for several seconds.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a note.
    ///     - Any other error that might occur during the request, such as ``RainmakerError/unexpectedStatus(code:)`` when the server cannot create a file of the sanitized name at all.
    ///
    func createNote(title: String, category: String = "", content: String = "", modification: Date? = nil, isFavorite: Bool = false) async throws -> Note {
        try requireCredentials()
        logger.debug("Creating a note...")

        // A moment without a positive number of whole seconds is left out, which the server takes as a request to keep the moment it wrote the file at.
        let body = NoteCreationRequest(title: title, category: category, content: content, modified: modification?.wholeSecondsSince1970, favorite: isFavorite)
        let request = try makeNotesAPIRequest(for: "notes", method: .post, jsonBody: encodeNotesAPIBody(body))
        let (data, _) = try await notesAPIResponse(for: request)
        let note = try decodeNotesAPIPayload(Note.self, from: data, describing: "the created note")
        logger.debug("Created note \(note.id).")

        return note
    }

    ///
    /// Change a note of the authenticated user and return it as the server stored it, optionally only if it is still the one a given entity tag was taken from.
    ///
    /// Only the values which are given are sent, and the server leaves everything else of the note as it is. A value equal to the one the note already has changes nothing, and a call which gives no value at all returns the note as ``note(_:)`` would. This is a standalone call which needs nothing but credentials and the note's identifier, so it suits a single action such as one of Shortcuts as well as a client keeping its own copy of the notes.
    ///
    /// When `entityTag` is given, the request carries it in its `If-Match` header and the server only changes the note while that is still its ``Note/entityTag``. Otherwise it changes nothing and the call throws ``RainmakerError/noteConflict(current:)``, which carries the note as the server has it now, content and entity tag included. That is what lets a caller resolve the conflict without a further request: apply its change to the current note again, for example append its text to the current ``Note/content`` rather than replace it, and retry with the current note's entity tag. Without an entity tag, the change applies to whatever the note is by then, so the last writer wins. A tag with or without quotes and with a `W/` prefix is accepted alike.
    ///
    /// The server applies the values one after the other, in the order content, modification, title and category, and favorite, each as a write of its own, so a change is not atomic. When a later step fails, for example because the file is locked or because a title cannot be used as a file name, the earlier steps remain applied, and the error does not say which. Retrieve the note through ``note(_:)`` after an error to learn what it is now.
    ///
    /// - A new ``Note/content`` replaces the text of the note.
    /// - A `modification` is stamped onto the note's file after the content was written, so sending it along with the content keeps the moment the caller wrote the text at, while new content without it is stamped with the moment the server wrote it. A moment at or before the Unix epoch is left out as if it was not given.
    /// - A new title renames the note's file and a new category moves it to the matching folder, both sanitized as ``createNote(title:category:content:modification:isFavorite:)`` describes, so a caller has to adopt the ``Note/title``, ``Note/category`` and ``Note/path`` of the result. An empty category moves the note out of every category. The note keeps its ``Note/id`` either way, and on releases of the notes app which keep attachments per note, see ``Notes/storesAttachmentsPerNote``, its `.attachments.<id>` folder moves along. A category folder left empty is removed.
    /// - ``Note/isFavorite`` is not stored in the note's file but with the account's favorites, so changing nothing else needs no permission to write the note and works on a note which ``Note/isReadOnly`` as well. It changes the note's entity tag all the same.
    ///
    /// Every other change of a note which is read-only for the authenticated user, for example one shared without write access, is refused with ``RainmakerError/readOnly``.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - id: The ``Note/id`` of the note to change.
    ///     - title: The new title, or `nil` to keep the current one. Defaults to `nil`.
    ///     - category: The new category, with `/` delimiting sub-categories and an empty string for none, or `nil` to keep the current one. Defaults to `nil`.
    ///     - content: The new text, or `nil` to keep the current one. Defaults to `nil`.
    ///     - modification: The moment to stamp the note with as its ``Note/modification``, or `nil` to leave it to the server. It is sent in whole seconds since the Unix epoch. Defaults to `nil`.
    ///     - isFavorite: Whether the note is to be marked as a favorite, or `nil` to keep the current state. Defaults to `nil`.
    ///     - entityTag: The ``Note/entityTag`` of the copy the change is based on, to change the note only while it is still that copy, or `nil` to change it whatever it is by then. Defaults to `nil`.
    ///
    /// - Returns: The note as the server stored it after the change, including its new entity tag and the sanitized title and category.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the account has no note with this identifier.
    ///     - ``RainmakerError/noteConflict(current:)`` when `entityTag` is given but the note changed on the server since, in which case nothing was changed.
    ///     - ``RainmakerError/readOnly`` when the note cannot be written by the authenticated user.
    ///     - ``RainmakerError/insufficientStorage`` when the account's quota leaves no room for the new content.
    ///     - ``RainmakerError/locked`` when the note's file is locked, after the server already retried for several seconds.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a note.
    ///     - Any other error that might occur during the request.
    ///
    func updateNote(_ id: Int, title: String? = nil, category: String? = nil, content: String? = nil, modification: Date? = nil, isFavorite: Bool? = nil, ifMatching entityTag: String? = nil) async throws -> Note {
        try requireCredentials()
        logger.debug("Updating note \(id)...")

        var headerFields = [String: String]()

        // The server compares the header against the tag it computed, quoted, so the tag is normalized the same way as for If-None-Match.
        if let entityTag {
            headerFields["If-Match"] = entityTag.unquotedEntityTag.quotedEntityTag
        }

        let body = NoteUpdateRequest(title: title, category: category, content: content, modified: modification?.wholeSecondsSince1970, favorite: isFavorite)
        let request = try makeNotesAPIRequest(for: "notes/\(id)", method: .put, headerFields: headerFields, jsonBody: encodeNotesAPIBody(body))
        let (data, _) = try await notesAPIResponse(for: request)

        return try decodeNotesAPIPayload(Note.self, from: data, describing: "the updated note")
    }

    ///
    /// Delete a note of the authenticated user.
    ///
    /// The server deletes the note's file like any other file deleted on the server, which puts it into the trash bin when the server keeps one, and it removes the category folder the note leaves empty. On releases of the notes app which keep attachments per note, see ``Notes/storesAttachmentsPerNote``, it deletes the note's `.attachments.<id>` folder along with it, while older releases leave the attachments where they are. This is a standalone call which needs nothing but credentials and the note's identifier, so it suits a single action such as one of Shortcuts as well as a client keeping its own copy of the notes.
    ///
    /// A note which does not exist is reported as ``RainmakerError/notFound``, which a caller deleting a note can take as the note being gone already, for example when it retries a deletion whose response was lost. An absent notes app is reported as ``RainmakerError/appUnavailable(app:)`` instead, as with ``notes()``.
    ///
    /// Unlike ``updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``, this offers no entity tag to make the deletion conditional on, because the server does not check one when it deletes a note. A caller which must not delete a note changed elsewhere can check through ``note(_:ifChangedFrom:)`` first, which narrows that window but cannot close it.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - id: The ``Note/id`` of the note to delete.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the account has no note with this identifier.
    ///     - ``RainmakerError/readOnly`` when the note cannot be deleted by the authenticated user.
    ///     - ``RainmakerError/locked`` when the note's file is locked, after the server already retried for several seconds.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - Any other error that might occur during the request.
    ///
    func deleteNote(_ id: Int) async throws {
        try requireCredentials()
        logger.debug("Deleting note \(id)...")

        let request = try makeNotesAPIRequest(for: "notes/\(id)", method: .delete)

        // The server answers with an empty list, which carries nothing worth decoding.
        _ = try await notesAPIResponse(for: request)
        logger.debug("Deleted note \(id).")
    }

    ///
    /// Retrieve a file a note refers to, such as an image embedded into it, into memory.
    ///
    /// The path is relative to the folder of the note's category, which is the folder the note's file is in. It is what ``addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` returned, or what the note's text references, after percent-decoding the reference. The server reads `\` as `/`, skips empty components and resolves `..` as a step up, but never above the notes folder, so a path reaches every file in the notes folder and nothing outside of it. Attachments uploaded through the notes app land in a folder named `.attachments.<id>` next to the note on releases which keep them per note, see ``Notes/storesAttachmentsPerNote``, and right next to the note on older releases. ``NoteAttachmentReference/decode(_:)`` turns a reference in the note's text into such a path, and ``NoteAttachmentPath/resolve(_:relativeTo:)`` tells which file in the notes folder the server resolves it to.
    ///
    /// This is a standalone call which needs nothing but credentials, the note's identifier and the path, so it suits a single action such as one of Shortcuts as well as a client keeping its own copy of the notes. It runs within the calling task, so cancelling that task cancels the request. The whole file is held in memory, so a large file or a process with little memory to spare, such as an extension, is better served by ``downloadAttachment(at:ofNote:to:force:)``, which writes it to a local file instead.
    ///
    /// Unlike every other notes feature, the notes app answers this request without its version header and reports every failure the same way, with `404`: a note which does not exist, a path which names nothing or a folder, and a file it cannot read. An absent notes app answers `404` as well, so all of these are reported as ``RainmakerError/notFound`` and cannot be told apart, which is why the ``Notes`` capability is the way to learn whether the app is there. A release of the notes app older than ``Notes/minimumAPIVersion`` does not know the path at all and answers with its version header, which is reported as ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``.
    ///
    /// The request bypasses the local HTTP cache, because the server allows caching an attachment for an hour while it sends neither an entity tag nor a modification moment which a later request could be made conditional on. Keep what this returns in a store of your own instead, keyed by server, account, note and path. Bypassing the cache does not keep the session from storing the response in its `URLCache` though, which a session whose configuration keeps one on disk does, and a session shared by several accounts should not keep one at all. See ``init(address:password:user:session:webSocket:userAgent:)`` for a fitting configuration.
    ///
    /// - Parameters:
    ///     - path: The path of the file relative to the folder of the note's category, as ``addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` returned it or as the note references it after percent-decoding.
    ///     - noteId: The ``Note/id`` of the note the path is relative to.
    ///
    /// - Returns: The bytes of the file together with their MIME type.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the note or the file does not exist, the file cannot be read, or the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when the notes app is older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///     - Any other error that might occur during retrieval.
    ///
    func attachment(at path: String, ofNote noteId: Int) async throws -> NoteAttachment {
        try requireCredentials()
        logger.debug("Fetching an attachment of note \(noteId)...")

        let request = try makeAttachmentRetrievalRequest(at: path, ofNote: noteId)
        let (data, urlResponse) = try await session.data(for: request)
        let response = try validateAttachmentRetrieval(urlResponse)

        return NoteAttachment(data: data, contentType: attachmentContentType(of: response))
    }

    ///
    /// Retrieve a file a note refers to, such as an image embedded into it, into a local file.
    ///
    /// This is the counterpart of ``attachment(at:ofNote:)`` for a file which is not to be held in memory: the session streams the file to disk, and it is put in place only once it arrived completely and successfully, so a failed or cancelled call never leaves a partial file at the destination. Everything about the path, the statuses and caching is the same as there.
    ///
    /// The destination is the location of the file itself, not of the folder it goes to, and that folder has to exist. When a file exists there already and `force` is not set, the call throws ``RainmakerError/fileAlreadyExists(_:)`` before anything is sent, and once more when such a file appeared while the download was in progress. With `force` set, an existing file is replaced, and it is kept intact until the new one is completely in place.
    ///
    /// - Parameters:
    ///     - path: The path of the file relative to the folder of the note's category, as ``addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` returned it or as the note references it after percent-decoding.
    ///     - noteId: The ``Note/id`` of the note the path is relative to.
    ///     - destination: The local location to write the file to, in a folder which exists.
    ///     - force: Whether to replace a file which exists at the destination. Defaults to `false`.
    ///
    /// - Returns: The location the file was written to, which is `destination`, together with its MIME type.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/fileAlreadyExists(_:)`` when a file exists at the destination and `force` is not set.
    ///     - ``RainmakerError/notFound`` when the note or the file does not exist, the file cannot be read, or the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when the notes app is older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///     - Any other error that might occur during retrieval or while putting the file in place.
    ///
    func downloadAttachment(at path: String, ofNote noteId: Int, to destination: URL, force: Bool = false) async throws -> NoteAttachmentFile {
        try requireCredentials()
        logger.debug("Downloading an attachment of note \(noteId) to \"\(destination.compatibilityPath(percentEncoded: false))\"...")

        // Checked before the download so that a call which cannot succeed sends nothing.
        if force == false {
            try fileManager.assertFileDoesNotExist(at: destination)
        }

        let request = try makeAttachmentRetrievalRequest(at: path, ofNote: noteId)
        let (location, urlResponse) = try await session.download(for: request, delegate: nil)

        // The session leaves the payload in a temporary location, which would otherwise be left behind on every failure below, and which is gone already once the payload was moved on.
        defer {
            try? fileManager.removeItem(at: location)
        }

        let response = try validateAttachmentRetrieval(urlResponse)

        // A file may have appeared at the destination while the download was in progress.
        if force == false {
            try fileManager.assertFileDoesNotExist(at: destination)
        }

        // The payload is staged next to its destination so that putting it in place stays within one volume, see ``URL/downloadStagingLocation()``.
        let stagingLocation = destination.downloadStagingLocation()

        defer {
            try? fileManager.removeItem(at: stagingLocation)
        }

        try fileManager.moveItem(at: location, to: stagingLocation)

        if fileManager.fileExists(atPath: destination.compatibilityPath(percentEncoded: false)) {
            // Replacing keeps the existing file intact until the new one is completely in place, unlike deleting it first.
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagingLocation)
        } else {
            try fileManager.moveItem(at: stagingLocation, to: destination)
        }

        return NoteAttachmentFile(location: destination, contentType: attachmentContentType(of: response))
    }

    ///
    /// Attach a local file to a note of the authenticated user and return the path the server stored it at.
    ///
    /// The file is sent as the field `file` of a form, as the web interface of the notes app uploads it. Its body is staged in a temporary file which is copied from `source` through a small buffer and removed again when the call ends, whatever its outcome, so neither the file nor the body is held in memory. The call runs within the calling task, so cancelling that task cancels the upload. It needs nothing but credentials and the note's identifier, so it suits a single action such as one of Shortcuts as well as a client keeping its own copy of the notes.
    ///
    /// Where the file ends up and therefore what this returns depends on the release of the notes app, see ``Notes/storesAttachmentsPerNote``:
    ///
    /// - Releases which keep attachments per note store the file in the folder `.attachments.<id>` next to the note under the given name, appending a number such as `" (1)"` before its extension when the name is taken, and return `.attachments.<id>/<name>`. They refuse a name which is not a valid file name on the server with `400`.
    /// - Older releases store the file right next to the note under a random name of 32 hexadecimal digits followed by a dot and what follows the last dot of the given name, or all of the given name when it has no dot, and return that name.
    ///
    /// The server's form handling keeps only what follows the last `/` or `\` of the name, as it does for every uploaded file. The returned path is relative to the folder of the note's category and is what ``attachment(at:ofNote:)``, ``downloadAttachment(at:ofNote:to:force:)`` and ``deleteAttachment(at:ofNote:)`` take.
    ///
    /// Adding an attachment does not change the note. To embed it, the caller changes the note's content through ``updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` to reference the returned path, for example as `![](.attachments.123/Photo%20%281%29.png)`. The notes app's editor encodes each component of such a reference as JavaScript's `encodeURIComponent` does and additionally encodes `!`, `'`, `(`, `)` and `*`, which keeps a name from ending the markdown link early. ``NoteAttachmentReference/markdown(alt:path:)`` builds such a reference from the returned path.
    ///
    /// > Important: Adding an attachment is not idempotent. Every call which reaches the server stores another file, and a call whose response was lost may have stored one all the same. The notes app offers no way to list the attachments of a note, but they are ordinary files, which ``enumerate(at:recursively:)->[Item]`` lists in the folder the note's ``Note/path`` names.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - source: The local file to attach.
    ///     - noteId: The ``Note/id`` of the note to attach the file to.
    ///     - fileName: The name to store the file under, or `nil` for the last component of `source`. Defaults to `nil`.
    ///
    /// - Returns: The path the server stored the file at, relative to the folder of the note's category.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the account has no note with this identifier.
    ///     - ``RainmakerError/locked`` when a file the server has to write is locked, after the server already retried for several seconds.
    ///     - ``RainmakerError/methodNotAllowed`` when the notes app is older than ``Notes/minimumAPIVersion`` and therefore does not offer the upload at all.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when the response does not advertise ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry the stored path.
    ///     - Any other error that might occur while staging or sending the file, such as ``RainmakerError/unexpectedStatus(code:)`` with `400` for a name the server refuses and with `500` for a failure to store the file, for example because the quota is exceeded or the note is shared without permission to change it.
    ///
    func addAttachment(_ source: URL, toNote noteId: Int, fileName: String? = nil) async throws -> String {
        try requireCredentials()
        logger.debug("Adding an attachment to note \(noteId)...")

        let form = MultipartFormData()
        let body = makeMultipartStagingLocation()

        // The staged body is removed whatever the outcome, also when staging it failed halfway.
        defer {
            try? fileManager.removeItem(at: body)
        }

        try form.writeFile(from: source, fieldName: "file", fileName: fileName ?? source.lastPathComponent, to: body, bufferSize: Self.stagingBufferSize)

        return try await uploadAttachment(stagedAt: body, as: form, toNote: noteId)
    }

    ///
    /// Attach the given bytes as a file to a note of the authenticated user and return the path the server stored it at.
    ///
    /// This is the counterpart of ``addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` for bytes already in memory, for example an image a Shortcuts action was handed, which is why the name to store them under is required. Everything about where the file ends up, what this returns and how it fails is the same as there. The bytes are written into a staged body which is sent through an upload task and removed when the call ends, as there.
    ///
    /// - Parameters:
    ///     - data: The bytes to attach.
    ///     - noteId: The ``Note/id`` of the note to attach the bytes to.
    ///     - fileName: The name to store the bytes under, whose extension is what the server derives the type of the attachment from.
    ///
    /// - Returns: The path the server stored the file at, relative to the folder of the note's category.
    ///
    /// - Throws: The same errors as ``addAttachment(_:toNote:fileName:)-(URL,Int,String?)``.
    ///
    func addAttachment(_ data: Data, toNote noteId: Int, fileName: String) async throws -> String {
        try requireCredentials()
        logger.debug("Adding an attachment to note \(noteId)...")

        let form = MultipartFormData()
        let body = makeMultipartStagingLocation()

        defer {
            try? fileManager.removeItem(at: body)
        }

        try form.write(data, fieldName: "file", fileName: fileName, to: body)

        return try await uploadAttachment(stagedAt: body, as: form, toNote: noteId)
    }

    ///
    /// Delete a file attached to a note of the authenticated user.
    ///
    /// Only releases of the notes app which keep attachments per note offer this, see ``Notes/supportsAttachmentDeletion``, and older releases answer with ``RainmakerError/methodNotAllowed``. Those releases only delete a file in the note's own `.attachments.<id>` folder: of the path, only its last component counts, which names the file in that folder, so a path such as `.attachments.123/Photo.png` and the bare `Photo.png` delete the same file, and no path reaches any other file. A folder left empty is removed as well.
    ///
    /// Deleting an attachment does not change the note, so a caller removes any reference to it from the note's content through ``updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` as well. Deleting the note itself deletes all of its attachments along with it on these releases, see ``deleteNote(_:)``. This is a standalone call which needs nothing but credentials, the note's identifier and the path, so it suits a single action such as one of Shortcuts as well.
    ///
    /// A file which does not exist is reported as ``RainmakerError/notFound``, which a caller deleting an attachment can take as the attachment being gone already.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - path: The path of the attachment as ``addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` returned it, of which only the last component counts.
    ///     - noteId: The ``Note/id`` of the note the attachment belongs to.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the note or the attachment does not exist.
    ///     - ``RainmakerError/methodNotAllowed`` when the notes app does not offer the deletion of attachments, see ``Notes/supportsAttachmentDeletion``.
    ///     - ``RainmakerError/readOnly`` when the note cannot be changed by the authenticated user.
    ///     - ``RainmakerError/locked`` when the file is locked, after the server already retried for several seconds.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - Any other error that might occur during the request, such as ``RainmakerError/unexpectedStatus(code:)`` with `400` for a last component which is not a valid file name.
    ///
    func deleteAttachment(at path: String, ofNote noteId: Int) async throws {
        try requireCredentials()
        logger.debug("Deleting an attachment of note \(noteId)...")

        let request = try makeNotesAPIRequest(for: "attachment/\(noteId)", method: .delete, root: Self.notesAttachmentAPIRoot, queryItems: [URLQueryItem(name: "path", value: path)])

        // The server answers with an empty list, which carries nothing worth decoding.
        _ = try await notesAPIResponse(for: request)
        logger.debug("Deleted an attachment of note \(noteId).")
    }

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
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry the settings.
    ///     - Any other error that might occur during retrieval.
    ///
    func notesSettings() async throws -> NotesSettings {
        try requireCredentials()
        logger.debug("Fetching note settings...")

        let request = try makeNotesAPIRequest(for: "settings", method: .get)
        let (data, _) = try await notesAPIResponse(for: request)

        return try decodeNotesAPIPayload(NotesSettings.self, from: data, describing: "the note settings")
    }

    ///
    /// Change the settings the notes app keeps for the authenticated user and return them as the server stored them.
    ///
    /// Only the values which are given are sent, and the server keeps every other setting as it is. A call which gives no value at all changes nothing and returns the settings as ``notesSettings()`` would. This is a standalone call which needs nothing but credentials, so it suits a single action such as one of Shortcuts as well.
    ///
    /// The settings belong to the account rather than to a client, so a change applies to the app's web interface and to every other client of the account alike. The server validates every value and replaces what it cannot use rather than refusing the request, which is why a caller has to adopt the settings this returns rather than assume what it asked for:
    ///
    /// - The notes path is relative to the account's files. Both `/` and `\` delimit its components, empty components and `.` are dropped, and `..` removes the component before it, so the path cannot leave the account's files. An empty path means the root folder of the account's files.
    /// - A file suffix of `.md` or `.txt` is stored as it is. Any other suffix is stored as a custom one, of which every character other than the letters `A` to `Z` and `a` to `z`, the digits, `.` and `-` is removed, as are its leading dots, before a single dot is put in front of it. A suffix with nothing left becomes `.md`.
    /// - A note mode the server does not offer the account, which is ``NoteMode/rich`` when the Text app is not enabled for it, is replaced by the server's default mode.
    ///
    /// Some settings change which notes the server lists, and a client keeping its own copy of the notes has to treat such a change like a different set of notes and retrieve them anew, for example through ``notes(changedSince:)`` with the Unix epoch:
    ///
    /// - Changing ``NotesSettings/notesPath`` does not move any note. The notes app looks for notes in the new folder from then on, and creates it when it does not exist yet the next time it is asked for the notes, so the notes in the old folder are no longer listed while those already in the new one are. The ``Notes/notesPath`` the capabilities advertise follows the setting as well.
    /// - Changing ``NotesSettings/showsHiddenFiles`` decides whether notes and categories whose names start with a dot are listed, see there.
    /// - Changing ``NotesSettings/fileSuffix`` gives the notes created from then on that extension. The app reads files with the extensions `.txt`, `.org`, `.markdown`, `.md` and `.note` as notes whatever the setting, and in addition those with the custom suffix set most recently, so replacing one custom suffix with another one makes the notes of the former disappear from the listings unless their extension is among those.
    ///
    /// The notes app keeps ``NotesSettings/showsHiddenFiles`` and ``NotesSettings/loadsRecentNoteOnStartUp`` since release 6.1.0. Older releases ignore them, which the returned settings show by leaving them `nil`.
    ///
    /// Credentials are required: the settings are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - notesPath: The path of the folder to store the notes in, relative to the account's files and sanitized as described above, or `nil` to keep the current one. Defaults to `nil`.
    ///     - fileSuffix: The file extension to give the notes created from now on, sanitized as described above, or `nil` to keep the current one. Defaults to `nil`.
    ///     - noteMode: The way the web interface is to present a note when it is opened, or `nil` to keep the current one. Defaults to `nil`.
    ///     - showsHiddenFiles: Whether the web interface is to list files and folders whose names start with a dot, or `nil` to keep the current setting. Defaults to `nil`.
    ///     - loadsRecentNoteOnStartUp: Whether the web interface is to open the most recently edited note when it starts, or `nil` to keep the current setting. Defaults to `nil`.
    ///
    /// - Returns: The notes app's settings for the authenticated user as the server stored them after the change, including the sanitized values.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry the settings.
    ///     - Any other error that might occur during the request.
    ///
    func updateNotesSettings(notesPath: String? = nil, fileSuffix: String? = nil, noteMode: NoteMode? = nil, showsHiddenFiles: Bool? = nil, loadsRecentNoteOnStartUp: Bool? = nil) async throws -> NotesSettings {
        try requireCredentials()
        logger.debug("Updating note settings...")

        // A setting sent as null is reset to its default by the server, so whatever is not given is left out of the body instead.
        let body = NotesSettingsUpdateRequest(notesPath: notesPath, fileSuffix: fileSuffix, noteMode: noteMode?.rawValue, showHidden: showsHiddenFiles, loadRecentOnStartUp: loadsRecentNoteOnStartUp)
        let request = try makeNotesAPIRequest(for: "settings", method: .put, jsonBody: encodeNotesAPIBody(body))
        let (data, _) = try await notesAPIResponse(for: request)

        return try decodeNotesAPIPayload(NotesSettings.self, from: data, describing: "the updated note settings")
    }
}

// MARK: - Notes API Helpers

extension Server {
    ///
    /// Build a request for an endpoint of the notes app's REST API, which every notes feature of ``Server`` sends through ``notesAPIResponse(for:uploadingFrom:allowsNotModified:)``, except for the retrieval of an attachment, whose response ``validateAttachmentRetrieval(_:)`` checks instead.
    ///
    /// The request is built by ``makeAppRequest(for:method:queryItems:)`` and therefore carries the credentials when there are any, so callers check for them with ``requireCredentials()`` first.
    /// Its cache policy is `reloadIgnoringLocalCacheData`, so a response is never answered from a `URLCache`, which could otherwise hide the server's real answer to a conditional request from the caller or serve bytes cached for another account sharing the same session.
    /// A JSON body is sent with the matching content type, and the given header fields are applied last so a caller can set conditional headers such as `If-Match` or `If-None-Match`.
    ///
    /// - Parameters:
    ///     - path: The path relative to `root`, e.g. `"notes"` or `"settings"`.
    ///     - method: The HTTP method to use.
    ///     - root: The root of the API the path is relative to, which is ``notesAPIRoot`` for everything but attachments and ``notesAttachmentAPIRoot`` for them.
    ///     - queryItems: The query parameters to append, in the order they should appear.
    ///     - headerFields: Additional header fields to set, which override those set before.
    ///     - jsonBody: The JSON body to send, usually written by ``encodeNotesAPIBody(_:)``, or `nil` for none.
    ///
    private func makeNotesAPIRequest(for path: String, method: Method, root: String = Server.notesAPIRoot, queryItems: [URLQueryItem] = [], headerFields: [String: String] = [:], jsonBody: Data? = nil) throws -> URLRequest {
        var request = try makeAppRequest(for: root + path, method: method, queryItems: queryItems)

        // A cached response would hide what the server answers now. For a conditional request that is the not modified status the caller asked about, and a session shared between accounts could even be answered with another account's notes.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
        }

        for (field, value) in headerFields {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return request
    }

    ///
    /// Perform a request built by ``makeNotesAPIRequest(for:method:root:queryItems:headerFields:jsonBody:)`` and map the status of its response onto ``RainmakerError``.
    ///
    /// This is what every notes feature shares: the mapping of the statuses the notes app answers with onto errors a caller can act upon, and the enforcement of ``Notes/minimumAPIVersion``.
    ///
    /// The notes app adds its `X-Notes-API-Versions` header to every response it sends itself, see `HTTPURLResponse.notesAPIVersions`, while a response the server or a proxy sends on its behalf lacks it. A status therefore only carries the notes app's meaning when the header is present, and it is checked before the version requirement so that an error the app reports is not mistaken for an outdated app:
    ///
    /// - `200` is a success, provided the header advertises a supported API version, and ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` otherwise.
    /// - `304` is returned as it is when `allowsNotModified` is set, for a conditional request, and ``RainmakerError/unexpectedStatus(code:)`` otherwise.
    /// - `403` with the header is ``RainmakerError/readOnly``.
    /// - `404` with the header is ``RainmakerError/notFound``, because the app reports a note or an attachment which does not exist, while `404` without it is ``RainmakerError/appUnavailable(app:)``, because the route itself does not exist.
    /// - `405` is ``RainmakerError/methodNotAllowed``, which the server answers before the app is involved, for a method an older release of the app does not route.
    /// - `412` with the header and a note as its body is ``RainmakerError/noteConflict(current:)``.
    /// - `423` with the header is ``RainmakerError/locked``.
    /// - `507` with the header is ``RainmakerError/insufficientStorage``.
    /// - Everything else, including `401`, is ``RainmakerError/unexpectedStatus(code:)``, which is what the event stream relies on to recognize rejected credentials.
    ///
    /// - Parameters:
    ///     - request: The request to perform.
    ///     - fileURL: The location of a local file to upload as the request body through an upload task, or `nil` to perform a data task.
    ///     - allowsNotModified: Whether a `304` response is an expected answer to a conditional request rather than an error.
    ///
    /// - Returns: The response body and the response itself, whose status is either `200` or, when allowed, `304`.
    ///
    private func notesAPIResponse(for request: URLRequest, uploadingFrom fileURL: URL? = nil, allowsNotModified: Bool = false) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let urlResponse: URLResponse

        if let fileURL {
            (data, urlResponse) = try await session.upload(for: request, fromFile: fileURL, delegate: nil)
        } else {
            (data, urlResponse) = try await session.data(for: request)
        }

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        let advertisedAPIVersions = response.notesAPIVersions
        let isFromNotesApp = advertisedAPIVersions.isEmpty == false

        switch response.status {
            case .ok:
                // Every response of the notes app advertises which versions of its API it can serve, so the requirement is enforced from the response already in hand rather than by asking for the server's capabilities first.
                guard Notes.supports(apiVersions: advertisedAPIVersions) else {
                    throw RainmakerError.unsupportedAPIVersion(app: Notes.key, required: Notes.minimumAPIVersion, advertised: advertisedAPIVersions)
                }

                return (data, response)

            case .notModified where allowsNotModified:
                return (data, response)

            case .forbidden where isFromNotesApp:
                throw RainmakerError.readOnly

            case .notFound where isFromNotesApp:
                throw RainmakerError.notFound

            case .notFound:
                // The route only exists while the notes app is installed and enabled, so a not found status the app did not send means the app is not there. Reporting it as such rather than as a missing note keeps a client from deleting its local notes because the app went away.
                throw RainmakerError.appUnavailable(app: Notes.key)

            case .methodNotAllowed:
                throw RainmakerError.methodNotAllowed

            case .preconditionFailed where isFromNotesApp:
                // The notes app sends the note as it currently is along with the conflict, so the caller can resolve it without another request. A body which is not a note leaves nothing to resolve with, so it is reported as the bare status instead.
                guard let current = try? jsonDecoder.decode(Note.self, from: data) else {
                    throw RainmakerError.unexpectedStatus(code: response.statusCode)
                }

                throw RainmakerError.noteConflict(current: current)

            case .locked where isFromNotesApp:
                throw RainmakerError.locked

            case .insufficientStorage where isFromNotesApp:
                throw RainmakerError.insufficientStorage

            default:
                throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    ///
    /// Build the request ``attachment(at:ofNote:)`` and ``downloadAttachment(at:ofNote:to:force:)`` send for a file a note refers to.
    ///
    /// It is built by ``makeNotesAPIRequest(for:method:root:queryItems:headerFields:jsonBody:)`` below ``notesAttachmentAPIRoot`` and therefore bypasses the local cache as well, while it announces that it accepts any type, because the response is the file itself rather than JSON. The path is sent as the `path` parameter, percent-encoded through ``makeAppRequest(for:method:queryItems:)`` so that names with characters such as `+` or `&` arrive as they are.
    ///
    /// - Parameters:
    ///     - path: The path of the file relative to the folder of the note's category.
    ///     - noteId: The ``Note/id`` of the note the path is relative to.
    ///
    private func makeAttachmentRetrievalRequest(at path: String, ofNote noteId: Int) throws -> URLRequest {
        try makeNotesAPIRequest(for: "attachment/\(noteId)", method: .get, root: Self.notesAttachmentAPIRoot, queryItems: [URLQueryItem(name: "path", value: path)], headerFields: ["Accept": "*/*"])
    }

    ///
    /// Map the status of a response to a request built by ``makeAttachmentRetrievalRequest(at:ofNote:)`` onto ``RainmakerError`` and return the response when it is a success.
    ///
    /// This differs from ``notesAPIResponse(for:uploadingFrom:allowsNotModified:)`` because the notes app sends the file without its version header and answers every failure with a bare `404`, so neither the version requirement nor the meaning of a status can rest on that header:
    ///
    /// - `200` is a success.
    /// - `404` is ``RainmakerError/notFound``, whether the note, the file or the app itself is missing.
    /// - Any other status from a release of the notes app older than ``Notes/minimumAPIVersion``, which recognizes itself by the header advertising only older versions, is ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``, because such a release does not know the path at all.
    /// - Everything else is ``RainmakerError/unexpectedStatus(code:)``.
    ///
    /// - Parameters:
    ///     - urlResponse: The response to check.
    ///
    /// - Returns: The response as an `HTTPURLResponse`, whose status is `200`.
    ///
    private func validateAttachmentRetrieval(_ urlResponse: URLResponse) throws -> HTTPURLResponse {
        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        if response.status == .ok {
            return response
        }

        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        let advertisedAPIVersions = response.notesAPIVersions

        // An outdated release routes the unknown path to its catch-all, which answers with an error and the versions it serves.
        if advertisedAPIVersions.isEmpty == false, Notes.supports(apiVersions: advertisedAPIVersions) == false {
            throw RainmakerError.unsupportedAPIVersion(app: Notes.key, required: Notes.minimumAPIVersion, advertised: advertisedAPIVersions)
        }

        throw RainmakerError.unexpectedStatus(code: response.statusCode)
    }

    ///
    /// The MIME type of a file ``attachment(at:ofNote:)`` or ``downloadAttachment(at:ofNote:to:force:)`` received, as ``NoteAttachment/contentType`` and ``NoteAttachmentFile/contentType`` report it.
    ///
    /// The notes app always states one, but a response without it is taken to be `application/octet-stream`, as HTTP prescribes for a body of unknown type, rather than failing a call whose file arrived intact.
    ///
    /// - Parameters:
    ///     - response: The successful response to read the type from.
    ///
    private func attachmentContentType(of response: HTTPURLResponse) -> String {
        response.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
    }

    ///
    /// A new location in the temporary directory to stage the ``MultipartFormData`` body of an upload of an attachment at, which the caller removes once it has been sent.
    ///
    private func makeMultipartStagingLocation() -> URL {
        fileManager.temporaryDirectory.appendingCompatibility(component: "Rainmaker-\(UUID().uuidString).multipart", directoryHint: .notDirectory)
    }

    ///
    /// Send a staged ``MultipartFormData`` body as a new attachment of a note and return the path the server stored it at, which both variants of ``addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` end in.
    ///
    /// The body is sent from its file through an upload task by ``notesAPIResponse(for:uploadingFrom:allowsNotModified:)``, which maps the statuses as for every other notes feature, because the notes app answers an upload with its version header.
    ///
    /// - Parameters:
    ///     - body: The location of the staged body.
    ///     - form: The body, whose boundary the request announces.
    ///     - noteId: The ``Note/id`` of the note to attach the file to.
    ///
    private func uploadAttachment(stagedAt body: URL, as form: MultipartFormData, toNote noteId: Int) async throws -> String {
        let request = try makeNotesAPIRequest(for: "attachment/\(noteId)", method: .post, root: Self.notesAttachmentAPIRoot, headerFields: ["Content-Type": form.contentType])
        let (data, _) = try await notesAPIResponse(for: request, uploadingFrom: body)
        let path = try decodeNotesAPIPayload(AttachmentUploadResponse.self, from: data, describing: "the added attachment").filename
        logger.debug("Added an attachment to note \(noteId).")

        return path
    }

    ///
    /// Build the request ``notes(changedSince:)``, ``notes(changedSince:ifChangedFrom:)`` and their chunked counterparts send for the notes which changed since a given moment.
    ///
    /// The `category` parameter the server also accepts is never sent, because it narrows the identifiers of the notes which were not sent in full as well, which would make every note outside the category look deleted.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, sent as the `pruneBefore` parameter in whole seconds since the Unix epoch.
    ///     - chunkSize: The number of notes to send in full at most, sent as the `chunkSize` parameter after raising it to at least one, or `nil` to have the server answer in a single response.
    ///     - chunkCursor: The cursor to continue a chunked retrieval from, sent as the `chunkCursor` parameter, or `nil` for none.
    ///     - headerFields: Additional header fields to set, such as `If-None-Match`.
    ///
    private func makeNoteChangesRequest(changedSince: Date, chunkSize: Int? = nil, chunkCursor: String? = nil, headerFields: [String: String] = [:]) throws -> URLRequest {
        // A moment at or before the Unix epoch has no positive number of seconds to express it, and pruning before it would exclude nothing anyway, so the server is asked not to prune at all.
        let pruneBefore = changedSince.wholeSecondsSince1970 ?? 0
        var queryItems = [URLQueryItem(name: "pruneBefore", value: String(pruneBefore))]

        // The server takes a chunk size of zero as a request not to split the response, so a caller asking for chunks always gets them, with at least one note per chunk.
        if let chunkSize {
            queryItems.append(URLQueryItem(name: "chunkSize", value: String(max(1, chunkSize))))
        }

        if let chunkCursor {
            queryItems.append(URLQueryItem(name: "chunkCursor", value: chunkCursor))
        }

        return try makeNotesAPIRequest(for: "notes", method: .get, queryItems: queryItems, headerFields: headerFields)
    }

    ///
    /// Read a successful response to a request built by ``makeNoteChangesRequest(changedSince:chunkSize:chunkCursor:headerFields:)`` into ``NoteChanges``.
    ///
    /// The body is split into the notes sent in full and the identifiers of those sent as identifiers alone, see `NoteEntry`, while the headers supply ``NoteChanges/lastModified``, ``NoteChanges/entityTag``, ``NoteChanges/chunkCursor`` and ``NoteChanges/pendingCount``.
    /// A header which is absent or cannot be read leaves its value `nil` rather than failing, because the notes themselves are what the caller cannot do without.
    ///
    /// - Parameters:
    ///     - data: The response body.
    ///     - response: The response, whose headers are read.
    ///
    private func makeNoteChanges(from data: Data, response: HTTPURLResponse) throws -> NoteChanges {
        let entries = try decodeNotesAPIPayload([NoteEntry].self, from: data, describing: "the notes")

        var changed = [Note]()
        var unchanged = [Int]()

        for entry in entries {
            switch entry {
                case let .changed(note): changed.append(note)
                case let .unchanged(id): unchanged.append(id)
            }
        }

        let lastModified = response.value(forHTTPHeaderField: "Last-Modified").flatMap(Date.init(httpDate:))
        let entityTag = response.value(forHTTPHeaderField: "ETag").map(\.unquotedEntityTag)
        let chunkCursor = response.value(forHTTPHeaderField: "X-Notes-Chunk-Cursor").flatMap { $0.isEmpty ? nil : $0 }
        let pendingCount = response.value(forHTTPHeaderField: "X-Notes-Chunk-Pending").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        return NoteChanges(changed: changed, unchanged: unchanged, lastModified: lastModified, entityTag: entityTag, chunkCursor: chunkCursor, pendingCount: pendingCount)
    }

    ///
    /// Decode the body of a successful response from ``notesAPIResponse(for:uploadingFrom:allowsNotModified:)`` with ``jsonDecoder``.
    ///
    /// None of the notes app's endpoints answers with an OCS envelope, so unlike every other JSON endpoint in this library there is no `meta` status vouching for a payload. A success response carrying something else entirely, for example an HTML login or maintenance page served by a proxy, therefore has to surface as ``RainmakerError/responseDecodingFailed(reason:)`` rather than as an opaque Foundation error. The payload is left out of that message so that note contents cannot leak into logs.
    ///
    /// - Parameters:
    ///     - type: The type to decode.
    ///     - data: The response body.
    ///     - subject: What is being decoded, for the error message, e.g. `"the notes"`.
    ///
    private func decodeNotesAPIPayload<Value: Decodable>(_ type: Value.Type, from data: Data, describing subject: String) throws -> Value {
        do {
            return try jsonDecoder.decode(type, from: data)
        } catch {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to decode \(subject): \(error)")
        }
    }

    ///
    /// Encode a request body for the notes app's REST API with ``jsonEncoder``, to be passed as the JSON body to ``makeNotesAPIRequest(for:method:root:queryItems:headerFields:jsonBody:)``.
    ///
    /// - Parameters:
    ///     - value: The value to encode, usually a data transfer object shaped as the notes app expects it.
    ///
    private func encodeNotesAPIBody(_ value: some Encodable) throws -> Data {
        try jsonEncoder.encode(value)
    }
}
