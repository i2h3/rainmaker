# Notes

Retrieve, create, change and delete the notes of an account, attach files to them and change the settings of the notes app.

## Overview

The notes app is not part of a Nextcloud installation, so whether it is installed at all is advertised through the ``Notes`` capability, which also reports whether it is new enough to be usable.

### Retrieving Notes

The notes of an account are retrieved either all at once or, for a client keeping its own copy, only those the server recorded a change for since a given moment.
Such an incremental retrieval also reports the server's own moment to continue from next time as ``NoteChanges/lastModified`` and an entity tag with which ``Server/notes(changedSince:ifChangedFrom:)`` learns without a transfer that nothing changed.
A client which must not hold every changed note at once retrieves them in chunks of a bounded size instead, one at a time or as a stream of the chunks of one pass, of which only the last one says which notes still exist.
A client which does not need the text of the notes lists them as summaries instead, which carry everything else and spare the transfer of every note's text, in the same incremental, conditional and chunked ways.
A single note is retrieved by its identifier, also conditionally on its entity tag, which spares the transfer of its content while it did not change.

### Changing Notes

Notes are created, changed and deleted one at a time, and a change can be made conditional on the entity tag of the copy it is based on, so that a note changed elsewhere in the meantime is reported as ``RainmakerError/noteConflict(current:)`` together with its current state rather than overwritten.

### Attachments

Files such as images are attached to a note by uploading them, which returns the path a note's content references them by, relative to the folder of the note's category, and they are retrieved by that path into memory or streamed into a local file.
Some behaviours of the notes app are tied to its release rather than to its API version, which ``Notes/isAppVersion(atLeast:)`` and the helpers built on it, such as ``Notes/supportsAttachmentDeletion``, tell apart: only release 6.1.0 and newer keep the attachments of a note in a folder of their own and can delete them.
An attachment is retrieved bypassing the local HTTP cache, but a session still stores the response in its `URLCache`, so a session shared by several accounts or handling private files is best configured without one, see ``Server/init(address:password:user:session:webSocket:userAgent:)``.

### Settings

Notes are ordinary files, so ``NotesSettings`` says where to find them when reaching for them over WebDAV instead, and ``Note/path`` says where exactly the file of each note is.
Those settings can be changed as well, which may change which notes the server lists, so a client keeping its own copy retrieves them anew afterwards.

### Note Content

The helpers listed under Note Content predict what the notes app makes of a note's title and category, and reference attachments from a note's Markdown content the way the Nextcloud Text app does, without asking the server.
They are pure functions which need neither a ``Server`` nor a connection, so a single action such as one of Shortcuts can prepare a request with them or interpret a note's content.
The notes API never derives a title from the content, so ``NoteTitle/derive(fromContent:)`` is how a client gives a note the title the web interface would give it.
The server still has the last word, so a caller adopts the ``Note/title`` and ``Note/category`` it returns, which may for example carry a number appended to avoid a clash.
An attachment added through ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` only becomes part of the note once its content references it, and the Text app deletes files in the note's attachment folder which the content does not reference, so the reference has to be encoded exactly as ``NoteAttachmentReference/markdown(alt:path:)`` encodes it.

### Errors

The notes features map the statuses the notes app answers with onto dedicated cases, such as ``RainmakerError/readOnly``, ``RainmakerError/locked``, ``RainmakerError/insufficientStorage`` and ``RainmakerError/noteConflict(current:)``, but only when the response actually comes from that app, while anything a proxy or the server answers on its behalf stays ``RainmakerError/unexpectedStatus(code:)``.
An absent notes app is reported as ``RainmakerError/appUnavailable(app:)`` rather than as ``RainmakerError/notFound``, which is reserved for a note that does not exist, so a client keeping its own copy never mistakes a missing app for deleted notes, except when retrieving an attachment, which reports every failure including an absent app as ``RainmakerError/notFound``.
An outdated notes app is reported as ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``, and a request the installed release does not offer at all, such as deleting an attachment before release 6.1.0, as ``RainmakerError/methodNotAllowed``.

## Topics

### Retrieving Notes

- ``Server/notes()``
- ``Server/notes(changedSince:)``
- ``Server/notes(changedSince:ifChangedFrom:)``
- ``Server/notes(changedSince:chunkSize:continuingAfter:)``
- ``Server/notes(changedSince:chunkSize:ifChangedFrom:)``
- ``Server/noteChunks(changedSince:chunkSize:)``
- ``Server/note(_:)``
- ``Server/note(_:ifChangedFrom:)``
- ``Note``
- ``NoteChanges``
- ``ShareType``

### Retrieving Summaries

- ``Server/noteSummaries(changedSince:)``
- ``Server/noteSummaries(changedSince:ifChangedFrom:)``
- ``Server/noteSummaries(changedSince:chunkSize:continuingAfter:)``
- ``Server/noteSummaries(changedSince:chunkSize:ifChangedFrom:)``
- ``Server/noteSummaryChunks(changedSince:chunkSize:)``
- ``NoteSummary``
- ``NoteSummaryChanges``

### Changing Notes

- ``Server/createNote(title:category:content:modification:isFavorite:)``
- ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``
- ``Server/deleteNote(_:)``

### Attachments

- ``Server/attachment(at:ofNote:)``
- ``Server/downloadAttachment(at:ofNote:to:force:)``
- ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)``
- ``Server/addAttachment(_:toNote:fileName:)-(Data,Int,String)``
- ``Server/deleteAttachment(at:ofNote:)``
- ``NoteAttachment``
- ``NoteAttachmentFile``

### Settings

- ``Server/notesSettings()``
- ``Server/updateNotesSettings(notesPath:fileSuffix:noteMode:showsHiddenFiles:loadsRecentNoteOnStartUp:)``
- ``NotesSettings``
- ``NoteMode``

### Note Content

- ``NoteTitle``
- ``NoteCategory``
- ``NoteAttachmentReference``
- ``NoteAttachmentPath``
