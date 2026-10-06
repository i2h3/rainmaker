# Using Notes From App Intents

Build actions for Shortcuts, Siri and widgets on the notes features, each of which is a standalone call that needs no synchronization engine.

## Overview

An App Intent runs one action and ends: it creates a note from some text, appends to a note, attaches an image or looks something up.
Every notes method of ``Server`` suits that, because each one is a single request, or a short fixed sequence of requests, which needs nothing but a ``Server`` with credentials and keeps no state between calls.
Nothing has to be synchronized first, and nothing has to be torn down afterwards.

The intents below assume a function `makeServer()` of the app's own which reads the address and the credentials of the account from the app's keychain and creates a ``Server`` with a session configured as described in <doc:UsingNotesFromAppIntents#Bound-the-Time-an-Intent-Takes>.

### Create a Note From Text

The notes API never derives a title from the content, so an intent which is only handed some text derives the title the notes app's web interface would give it through ``NoteTitle/derive(fromContent:)``.
A text without anything usable as a title derives an empty title, for which the server substitutes its default title.

```swift
struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let server = try makeServer()
        let note = try await server.createNote(title: NoteTitle.derive(fromContent: text), content: text)

        return .result(value: note.title)
    }
}
```

The server sanitizes the title and numbers one already taken, so the intent reports the ``Note/title`` it returns rather than the one it sent.
Creating a note is not idempotent: when the response was lost, the note may have been created all the same, so an intent does not simply repeat the call.

### Append to a Note

Appending is a change based on the note's current content, so the intent makes it conditional on the ``Note/entityTag`` of the copy it appended to.
When the note changed elsewhere in the meantime, ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` changes nothing and throws ``RainmakerError/noteConflict(current:)`` with the note as the server has it now, so the intent appends to that one and tries again without retrieving it first.

```swift
func append(_ text: String, toNote id: Int, on server: Server) async throws -> Note {
    var note = try await server.note(id)

    for _ in 0 ..< 3 {
        // A note the server could not read carries a message about the failure in place of its text, which must not be written back.
        guard note.hasError == false else {
            throw AppendError.unreadable
        }

        do {
            return try await server.updateNote(note.id, content: note.content + "\n" + text, ifMatching: note.entityTag)
        } catch let RainmakerError.noteConflict(current: current) {
            note = current
        }
    }

    throw AppendError.keepsChanging
}
```

Without `ifMatching`, the last writer wins, and text typed into the note in the web interface while the intent ran would be lost.

### Add an Image to a Note

An image is uploaded as an attachment first and then referenced from the note's content, because adding an attachment does not change the note.
The reference has to be encoded exactly as the Nextcloud Text app encodes it, or a background job of that app deletes the file as unreferenced, which ``NoteAttachmentReference/markdown(alt:path:)`` takes care of.

```swift
struct AddImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Image to Note"

    @Parameter(title: "Note Identifier")
    var noteId: Int

    @Parameter(title: "Image")
    var image: IntentFile

    func perform() async throws -> some IntentResult {
        let server = try makeServer()
        let name = NoteAttachmentReference.sanitizeFileName(image.filename)
        let path = try await server.addAttachment(image.data, toNote: noteId, fileName: name)

        _ = try await append(NoteAttachmentReference.markdown(alt: name, path: path), toNote: noteId, on: server)

        return .result()
    }
}
```

``NoteAttachmentReference/sanitizeFileName(_:)`` removes the invisible characters Text leaves out of references, so that the stored name matches the name the reference decodes to.
The path the server returns depends on the release of the notes app, see ``Notes/storesAttachmentsPerNote``, and the reference works with either form.
Like creating a note, adding an attachment is not idempotent, which is why a conflict only repeats the append above and never the upload.
A large file which already is on disk is better attached through ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)``, which streams it instead of holding it in memory.

### Bound the Time an Intent Takes

Every call runs within the task which awaits it, so cancelling that task, as the system does with an intent it ends, cancels the request in flight.
The streams ``Server/noteChunks(changedSince:chunkSize:)`` and ``Server/noteSummaryChunks(changedSince:chunkSize:)`` request each chunk within the consuming task as well, and a stream which ended early did not deliver a complete pass, which its last chunk's `isComplete` tells.

The time a request may take is a property of the session the ``Server`` was created with, so an app gives its intents a session with timeouts short enough for an action someone waits for.
A session used from an intent also keeps no cache, because an intent runs in a process which may handle several accounts and private notes:

```swift
func makeServer() throws -> Server {
    let account = try AccountStore.current()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30

    return Server(address: account.address, password: account.appPassword, user: account.loginName, session: URLSession(configuration: configuration))
}
```

A request which times out throws the `URLError` the session reports, which an intent surfaces like any other error.
The errors worth a message of their own are ``RainmakerError/appUnavailable(app:)`` and ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``, which mean that the server lacks a notes app this library can use, and ``RainmakerError/notFound``, which means that the note was deleted.

### Index Notes Without Their Text

An intent or a background task which only needs the titles of the notes, for example to offer them as suggestions of an `EntityQuery` or to index them for Spotlight, lists them as summaries, so the text of every note is never downloaded.
``Server/noteSummaryChunks(changedSince:chunkSize:)`` keeps the memory a pass takes bounded by the chunk size, which suits an extension with little memory to spare.

```swift
for try await chunk in server.noteSummaryChunks(changedSince: .distantPast, chunkSize: 200) {
    let items = chunk.changed.map { summary in
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = summary.title
        attributes.contentModificationDate = summary.modification

        return CSSearchableItem(uniqueIdentifier: String(summary.id), domainIdentifier: summary.category, attributeSet: attributes)
    }

    try await CSSearchableIndex.default().indexSearchableItems(items)
}
```

A note picked from those suggestions is retrieved in full through ``Server/note(_:)`` when the intent runs, and ``NoteSummary/entityTag`` matches ``Note/entityTag``, so a summary is as good a basis for a conditional change as the note itself.
A client which keeps such an index up to date over time follows <doc:SynchronizingNotes> rather than listing everything again.
