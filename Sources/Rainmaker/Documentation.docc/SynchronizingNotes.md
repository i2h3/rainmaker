# Synchronizing Notes

Keep a local copy of the notes of an account in step with the server, transferring as little as possible and never losing a change made elsewhere.

## Overview

The notes app of a Nextcloud server keeps every note as an ordinary file and offers a REST API on top which reports what changed since a given moment.
A client keeping its own copy of the notes builds on four ideas: it asks for changes since the server's own moment of the previous call, it asks conditionally so that an unchanged account costs no transfer, it splits large transfers into chunks and derives deletions only from a complete answer, and it makes every change conditional on the copy it is based on.

Each method mentioned here is a standalone call which needs nothing but a ``Server`` with credentials, so the same calls serve a full synchronization engine as well as a single action, see <doc:UsingNotesFromAppIntents>.

### Check What the Server Offers

The notes app is not part of a Nextcloud installation, so whether it is there and new enough is worth asking before anything else.
Every notes feature requires the notes API in version ``Notes/minimumAPIVersion`` or newer, which the notes app serves since release 4.12.3, and ``Notes/isSupported`` tells whether a server advertises it.
Some behaviours are tied to a release of the app rather than to its API version, which ``Notes/isAppVersion(atLeast:)`` and the helpers built on it tell apart.

```swift
let capabilities = try await server.capabilities()

guard let notes = try capabilities.get(Notes.self), notes.isSupported else {
    return // The notes app is absent or too old for this library.
}

let canDeleteAttachments = notes.supportsAttachmentDeletion // Release 6.1.0 or newer.
```

A notes app which goes away later is reported as ``RainmakerError/appUnavailable(app:)`` by every notes call except the retrieval of an attachment (see below), never as ``RainmakerError/notFound``, which is reserved for a note that does not exist.
Where the retrieval of an attachment reports ``RainmakerError/notFound``, the ``Notes`` capability tells whether the app is still there.
A client therefore never mistakes a missing app for an account whose notes were all deleted.

### Retrieve Changes Since the Previous Call

``Server/notes(changedSince:)`` returns every note the server recorded a change for at or after the given moment in full, and reduces every other note to its identifier.
Both halves of the ``NoteChanges`` together are the complete set of notes the account has, which is what makes deletions detectable.

The moment is sent as the server's `pruneBefore` parameter and compared against the server's own record of when it noticed each note change, not against ``Note/modification``.
Pass `Date.distantPast` for the first call, which prunes nothing, and from then on the ``NoteChanges/lastModified`` of the previous result, which is the server's own clock at the time it started answering.
Never pass a note's ``Note/modification`` or the device's clock, because a note written long ago can still be one the server only noticed today.

A note the server could not read is listed with ``Note/hasError`` set and a message about the failure in place of its text.
Such a note still exists, so its identifier counts when deletions are derived, but its content must not replace a good local copy.

```swift
let changes = try await server.notes(changedSince: store.lastModified ?? .distantPast)

for note in changes.changed where note.hasError == false {
    store.upsert(note)
}

// Every identifier the server returned, the unreadable notes included, is a note which still exists.
store.deleteAll(exceptFor: changes.changed.map(\.id) + changes.unchanged)

// Remembered only once everything was applied, so an interrupted synchronization repeats rather than skips what it missed.
store.lastModified = changes.lastModified
store.entityTag = changes.entityTag
```

### Ask Conditionally

A client polling the server passes the ``NoteChanges/entityTag`` and the ``NoteChanges/lastModified`` of the previous result to ``Server/notes(changedSince:ifChangedFrom:)``.
The server answers with an empty `304 Not Modified` when it would send exactly what it sent along with that tag, which the method returns as `nil`.
On `nil`, keep the previous moment and tag for the next call, which never skips a change, because the server keeps every note which changed in the very second the moment names.

The server computes the tag from the body it would send, so the first call after a result which carried notes in full still receives a complete response, reducing those notes to their identifiers, and every further call answers `nil` until something changes.
`nil` deliberately differs from an empty ``NoteChanges``, which would claim that the account has no notes at all.

A single note is refreshed the same way through ``Server/note(_:ifChangedFrom:)`` with its ``Note/entityTag``, which spares the transfer of its content while it did not change and reports a deleted note as ``RainmakerError/notFound`` whatever the tag.

### Retrieve Changes in Chunks

A client which must not hold every changed note at once, such as an extension or a watch app, retrieves a pass in chunks of a bounded size.
``Server/noteChunks(changedSince:chunkSize:)`` streams the chunks of one pass and requests a chunk only when the consumer asks for the next one, so a consumer which applies each chunk before it continues needs no more memory than one chunk takes.

Only the last chunk of a pass, which ``NoteChanges/isComplete``, lists the identifiers of the notes the earlier chunks did not send in full, so deletions are derived from it alone and never from what a pass collected along the way.
Every chunk of one pass carries the same ``NoteChanges/lastModified``, which is remembered only once the last chunk was applied.

```swift
var lastChunk: NoteChanges?

for try await chunk in server.noteChunks(changedSince: store.lastModified ?? .distantPast, chunkSize: 50) {
    store.upsert(chunk.changed.filter { $0.hasError == false })
    lastChunk = chunk
}

// A stream which ended early, for example because its task was cancelled, did not deliver a complete pass.
guard let lastChunk, lastChunk.isComplete else {
    return
}

store.deleteAll(exceptFor: lastChunk.changed.map(\.id) + lastChunk.unchanged)
store.lastModified = lastChunk.lastModified
store.entityTag = lastChunk.entityTag
```

A pass interrupted, for example because the system suspended the app, continues later through ``Server/notes(changedSince:chunkSize:continuingAfter:)`` with the ``NoteChanges/chunkCursor`` of the last chunk applied and the same moment as before.
The first chunk of a new pass can be asked for conditionally through ``Server/notes(changedSince:chunkSize:ifChangedFrom:)`` with the tag of the last chunk of the previous pass.
The notes API also offers to narrow a listing down to a category, which this library never asks for, because that filter narrows the identifiers of the last chunk as well and would make every note outside the category look deleted.

### Leave Out the Text With Summaries

A client which lists notes but keeps no copy of their text, for example to index titles or to show a list, asks for summaries instead.
``Server/noteSummaries(changedSince:)``, ``Server/noteSummaries(changedSince:ifChangedFrom:)``, ``Server/noteSummaries(changedSince:chunkSize:continuingAfter:)``, ``Server/noteSummaries(changedSince:chunkSize:ifChangedFrom:)`` and ``Server/noteSummaryChunks(changedSince:chunkSize:)`` mirror the listings above and return ``NoteSummaryChanges`` with ``NoteSummary`` values, so the text of the notes is never downloaded.

The server only notices that it cannot read a note while it reads the text, which a summary listing asks it to skip, so a ``NoteSummary`` has no counterpart to ``Note/hasError``.
``NoteSummary/entityTag`` is the same tag ``Note/entityTag`` carries, so the text of a single note can be fetched when it is needed through ``Server/note(_:)`` or ``Server/note(_:ifChangedFrom:)``, and a change can be based on the summary through `ifMatching`.
The entity tag of a whole response is computed from its body, which holds no text in a summary listing, so keep the response tags of summary listings and of full listings apart: one only matches the other while neither response sends a note in full.

### Change Notes Without Losing Changes Made Elsewhere

``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` sends only the values it is given, and with the ``Note/entityTag`` of the copy the change is based on in `ifMatching` the server only applies it while that is still the note's tag.
Otherwise nothing is changed and the call throws ``RainmakerError/noteConflict(current:)``, which carries the note as the server has it now, so a client merges its change into that note and retries with the current tag without a further request.

```swift
do {
    let updated = try await server.updateNote(local.id, content: local.content, ifMatching: local.entityTag)
    store.upsert(updated)
} catch let RainmakerError.noteConflict(current: current) {
    let merged = merge(local, into: current)
    let updated = try await server.updateNote(current.id, content: merged.content, ifMatching: current.entityTag)
    store.upsert(updated)
}
```

The server applies the values of one change one after the other, so a change which fails halfway may leave the earlier values applied, and ``Server/note(_:)`` tells what the note is now.
The server sanitizes titles and categories, which become file and folder names, so adopt the ``Note/title``, ``Note/category`` and ``Note/path`` it returns, which ``NoteTitle/sanitize(_:)`` and ``NoteCategory/sanitize(_:)`` predict.

``Server/createNote(title:category:content:modification:isFavorite:)`` is not idempotent: every call which reaches the server creates another note, and the server numbers a title already taken rather than refuse it.
A call whose response was lost may have created the note all the same, so before repeating it, list the changes since the moment before the attempt and look for the note.
Passing the moment the note was written offline as `modification` keeps it as ``Note/modification``.

``Server/deleteNote(_:)`` cannot be made conditional, because the server checks no entity tag when it deletes, and a ``RainmakerError/notFound`` in answer to a deletion means that the note is gone already.

### Work With Attachments

Files such as images are attached to a note through ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` or ``Server/addAttachment(_:toNote:fileName:)-(Data,Int,String)``, which return the path the server stored the file at, relative to the folder of the note's category.
They are retrieved by that path through ``Server/attachment(at:ofNote:)`` into memory or ``Server/downloadAttachment(at:ofNote:to:force:)`` into a local file, and deleted through ``Server/deleteAttachment(at:ofNote:)``.
These requests go to the `v1.4` segment of the notes API rather than to `v1`, because releases of the notes app before 6.1.0 route attachments only there.

Where the file lands depends on the release of the notes app, see ``Notes/storesAttachmentsPerNote``:

- Release 6.1.0 and newer store it in a folder `.attachments.<id>` next to the note, under the given name with a number appended when it is taken, move that folder along when the note moves and delete it with the note.
- Older releases store it right next to the note under a random name, leave it behind when the note is deleted and cannot delete it through the API at all, which ``Server/deleteAttachment(at:ofNote:)`` reports as ``RainmakerError/methodNotAllowed`` and ``Notes/supportsAttachmentDeletion`` tells in advance.

Adding an attachment does not change the note: it becomes part of the note only once the note's content references it.
The Nextcloud Text app, which edits Markdown notes in the web interface, encodes each component of such a reference as JavaScript's `encodeURIComponent` does and additionally encodes `!`, `'`, `(`, `)` and `*`.
A background job of the Text app deletes files in the `.attachments.<id>` folder of a Markdown note which its content does not reference in exactly that form, so a reference built any other way can cost the file.
``NoteAttachmentReference/markdown(alt:path:)`` builds the reference the way Text does, ``NoteAttachmentReference/decode(_:)`` turns a reference back into the path the server takes, and ``NoteAttachmentReference/sanitizeFileName(_:)`` removes the invisible characters from a file name before upload which Text leaves out of references.

The retrieval of an attachment is the one notes request the app answers without its version header, and it reports every failure with a bare `404`, so ``RainmakerError/notFound`` there may also mean an absent notes app.
The notes app offers no way to list the attachments of a note, but they are ordinary files, which ``Server/enumerate(at:recursively:)->[Item]`` lists in the folder which contains the file ``Note/path`` names, or in its `.attachments.<id>` subfolder on releases which keep attachments per note, see ``Notes/storesAttachmentsPerNote``.

### Treat Changed Settings as a New Set of Notes

``Server/updateNotesSettings(notesPath:fileSuffix:noteMode:showsHiddenFiles:loadsRecentNoteOnStartUp:)`` can change which notes the server lists, for example by pointing it at another folder or by listing hidden files.
A client keeping its own copy retrieves the notes anew afterwards, starting from `Date.distantPast`.
The settings belong to the account rather than to a client, so another client may change them as well, which a client notices by comparing what ``Server/notesSettings()`` returns with what it saw before.
The settings ``NotesSettings/showsHiddenFiles`` and ``NotesSettings/loadsRecentNoteOnStartUp`` exist since release 6.1.0 of the notes app and are `nil` on older releases.

### Configure the Session for Several Accounts

Every request authenticates itself and refuses cookies, so one session can serve the ``Server`` objects of several accounts.
The notes requests bypass the local HTTP cache, but a session still stores their responses in its `URLCache`, which is keyed by URL alone while the same path of an attachment can stand for different files of different accounts.
A session shared by several accounts, or one which handles private notes, should therefore keep no cache at all, as ``Server/init(address:password:user:session:webSocket:userAgent:)`` describes:

```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.urlCache = nil
configuration.httpCookieStorage = nil
configuration.httpShouldSetCookies = false

let session = URLSession(configuration: configuration)
let work = Server(address: workAddress, password: workPassword, user: workUser, session: session)
let personal = Server(address: personalAddress, password: personalPassword, user: personalUser, session: session)
```

Keep the moment, the entity tags and the local copy apart per server and account as well, because neither a moment nor a tag means anything to another account.
