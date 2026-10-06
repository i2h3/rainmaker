# ``Rainmaker``

A simple Swift library to interact with Nextcloud programmatically.

## Overview

Rainmaker intentionally sticks to the basics and does not attempt to cover all the Nextcloud features.
It is stateless and is built using first-party frameworks like Foundation.
For the simplest use cases, you might prefer this over [NextcloudKit](https://github.com/nextcloud/NextcloudKit).

## Installation

Add this repository to your Xcode project package dependencies or to your Swift package dependencies in the package manifest.
This is the only method currently supported.

## Topics

### Command Line Interface

- <doc:CommandLineInterface>

### Services

- ``Server``

### Files

Browse, download, upload and reorganize the files of an account over WebDAV.
A file larger than the chunk size is uploaded in chunks the server assembles, which keeps large uploads within the request limits of the server and any reverse proxy in front of it; the ``ChunkedUpload`` capability advertises the limits a server suggests for that.

- ``Server/enumerate(at:recursively:)->AsyncThrowingStream<Item,Error>``
- ``Server/enumerate(at:recursively:)->[Item]``
- ``Server/info(_:)``
- ``Server/download(_:to:force:)``
- ``Server/upload(_:to:force:chunkSize:)``
- ``Server/createDirectory(_:)``
- ``Server/delete(_:)``
- ``Server/move(_:to:overwrite:)``

### Trash Bin

List, restore and permanently remove deleted items, which the server keeps in a per-account trash bin whose availability is advertised through the ``Trashing`` capability.

- ``Server/trash()``
- ``Server/restore(_:)-(String)``
- ``Server/restore(_:)-(TrashItem)``
- ``Server/emptyTrash()``

### Authentication

Obtain an app password through the server's login flow and revoke it again once it is no longer needed.

- ``Server/login()``
- ``Server/poll(_:token:)``
- ``Server/deleteAppPassword()``

### Data Models

- ``AvailableQuota``
- ``Item``
- ``Lock``
- ``LoginFlow``
- ``LoginResult``
- ``Permission``
- ``Quota``
- ``TrashItem``
- ``User``

### Observing Changes

Observe server-side changes over the `notify_push` WebSocket when available, falling back to polling otherwise, through a single stream of re-fetch hints.

- ``Server/events(_:)``
- ``Server/events(_:pollInterval:)``
- ``ServerEvent``
- ``ServerSubject``
- ``ServerEventOptions``

### Activity Stream

Retrieve what the server recorded about an account: files being created, changed and shared, calendar events being scheduled, and whatever else an installed app contributes.

- ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)``
- ``Server/activityFilters()``
- ``ActivityPage``
- ``ActivityItem``
- ``ActivityRichText``
- ``ActivityRichObject``
- ``ActivityPreview``
- ``ActivityFilter``
- ``ActivitySort``

### User Notifications

List what the server currently has queued for the authenticated user, which is the other thing worth re-fetching in response to ``ServerEvent/notifications``.
Whether and how many notifications are pending follows from the returned array, and whether the app providing them is installed at all is advertised through the ``Notifications`` capability.

- ``Server/notifications()``
- ``NotificationItem``

### User Avatars

Retrieve the picture a Nextcloud user is represented by, which is what a client needs to put a face beside the people an activity stream or a conversation names.

The server answers with an image for every user it knows, drawing one from their initials when that user uploaded none, so an absent picture is not reported as an absent response.
``UserAvatar/isCustom`` is the only thing that distinguishes the two, and a client with a monogram style of its own has to consult it or it will draw over the server's placeholder rather than in place of it.
Only two sizes are served, which is what ``AvatarSize`` models: the endpoint rounds any other value to one of them.
Each fetch bypasses the local HTTP cache, and the endpoint publishes no version marker, so cache images on a bounded lifetime and key entries by server, account, user, size and appearance.

- ``Server/userAvatar(_:size:darkTheme:)``
- ``UserAvatar``
- ``AvatarSize``

### Notes

Retrieve the notes of an account, either all of them at once or, for a client keeping its own copy, only those the server recorded a change for since a given moment.
Such an incremental retrieval also reports the server's own moment to continue from next time as ``NoteChanges/lastModified`` and an entity tag with which ``Server/notes(changedSince:ifChangedFrom:)`` learns without a transfer that nothing changed.
A client which must not hold every changed note at once retrieves them in chunks of a bounded size instead, one at a time or as a stream of the chunks of one pass, of which only the last one says which notes still exist.
A single note is retrieved by its identifier, also conditionally on its entity tag, which spares the transfer of its content while it did not change.
Notes are created, changed and deleted one at a time, and a change can be made conditional on the entity tag of the copy it is based on, so that a note changed elsewhere in the meantime is reported as ``RainmakerError/noteConflict(current:)`` together with its current state rather than overwritten.
Whether the app providing them is installed at all is advertised through the ``Notes`` capability, which matters more here than elsewhere because the notes app is not part of a Nextcloud installation, and which also reports whether it is new enough to be usable.
Notes are ordinary files, so ``NotesSettings`` says where to find them when reaching for them over WebDAV instead, and ``Note/path`` says where exactly the file of each note is.
Those settings can be changed as well, which may change which notes the server lists, so a client keeping its own copy retrieves them anew afterwards.
Files such as images are attached to a note by uploading them, which returns the path a note's content references them by, relative to the folder of the note's category, and they are retrieved by that path into memory or streamed into a local file.
Some behaviours of the notes app are tied to its release rather than to its API version, which ``Notes/isAppVersion(atLeast:)`` and the helpers built on it, such as ``Notes/supportsAttachmentDeletion``, tell apart: only release 6.1.0 and newer keep the attachments of a note in a folder of their own and can delete them.
An attachment is retrieved bypassing the local HTTP cache, but a session still stores the response in its `URLCache`, so a session shared by several accounts or handling private files is best configured without one, see ``Server/init(address:password:user:session:webSocket:userAgent:)``.
An absent notes app is reported as ``RainmakerError/appUnavailable(app:)`` rather than as ``RainmakerError/notFound``, which is reserved for a note that does not exist, so a client keeping its own copy never mistakes a missing app for deleted notes.

- ``Server/notes()``
- ``Server/notes(changedSince:)``
- ``Server/notes(changedSince:ifChangedFrom:)``
- ``Server/notes(changedSince:chunkSize:continuingAfter:)``
- ``Server/notes(changedSince:chunkSize:ifChangedFrom:)``
- ``Server/noteChunks(changedSince:chunkSize:)``
- ``Server/note(_:)``
- ``Server/note(_:ifChangedFrom:)``
- ``Server/createNote(title:category:content:modification:isFavorite:)``
- ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``
- ``Server/deleteNote(_:)``
- ``Server/attachment(at:ofNote:)``
- ``Server/downloadAttachment(at:ofNote:to:force:)``
- ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)``
- ``Server/addAttachment(_:toNote:fileName:)-(Data,Int,String)``
- ``Server/deleteAttachment(at:ofNote:)``
- ``Server/notesSettings()``
- ``Server/updateNotesSettings(notesPath:fileSuffix:noteMode:showsHiddenFiles:loadsRecentNoteOnStartUp:)``
- ``Note``
- ``NoteChanges``
- ``ShareType``
- ``NotesSettings``
- ``NoteMode``
- ``NoteAttachment``
- ``NoteAttachmentFile``

### Note Content

Predict what the notes app makes of a note's title and category, and reference attachments from a note's Markdown content the way the Nextcloud Text app does, without asking the server.
These are pure functions which need neither a ``Server`` nor a connection, so a single action such as one of Shortcuts can prepare a request with them or interpret a note's content.
The notes API never derives a title from the content, so ``NoteTitle/derive(fromContent:)`` is how a client gives a note the title the web interface would give it.
The server still has the last word, so a caller adopts the ``Note/title`` and ``Note/category`` it returns, which may for example carry a number appended to avoid a clash.
An attachment added through ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` only becomes part of the note once its content references it, and the Text app deletes files in the note's attachment folder which the content does not reference, so the reference has to be encoded exactly as ``NoteAttachmentReference/markdown(alt:path:)`` encodes it.

- ``NoteTitle``
- ``NoteCategory``
- ``NoteAttachmentReference``
- ``NoteAttachmentPath``

### Collectives

Retrieve the collectives of an account and the pages within one of them.
The Collectives app is not part of a Nextcloud installation, and unlike every other app covered here it advertises no capability at all, so whether it is available is answered by looking for the entry with the identifier `collectives` in ``Server/navigation()`` rather than through ``Server/capabilities()``.
Pages are returned flat and in the server's order; their hierarchy is reconstructed from ``CollectivePage/parentId``.

- ``Server/collectives()``
- ``Server/pages(inCollective:)``
- ``Collective``
- ``CollectivePage``
- ``MembershipLevel``

### Talk

Retrieve the conversations of an account and the image of a single one of them, which is what a client needs to surface conversations without taking part in them.
The Talk app is not part of a Nextcloud installation, and whether it is available is advertised through the ``Talk`` capability, which, unlike the ``Notes``, ``Notifications`` and ``Activity`` capabilities, is visible to anonymous clients as well.
Conversations come back in the server's own order, which is no order at all, so a client presenting a list sorts them by ``Conversation/lastActivity`` itself.
The image of a conversation is whatever the server resolved it to, from an uploaded picture to an icon it generated, and is commonly an SVG document rather than a bitmap.
Each explicit avatar fetch bypasses the local HTTP cache.
Cache images between displays, refreshing when ``Conversation/avatarVersion`` changes and periodically even if it does not, for example once a day.
In one-to-one conversations that version says nothing at all: it is the same value for every such conversation and never moves when the other person changes their profile picture.
Keep separate cached images for each server, account, conversation token and appearance.

- ``Server/conversations()``
- ``Server/conversationAvatar(_:darkTheme:)``
- ``Conversation``
- ``ConversationType``
- ``ConversationAvatar``

### Apps Navigation

List the server apps, such as Files, Photos and Activity, which the server advertises to the authenticated user so that a client can surface them in its own navigation.

- ``Server/navigation()``
- ``NavigationItem``

### Capabilities

- ``Server/capabilities()``
- ``CapabilitySet``
- ``Capability``
- ``Activity``
- ``ChunkedUpload``
- ``Notes``
- ``Notifications``
- ``PushNotifications``
- ``Talk``
- ``Theming``
- ``Trashing``
- ``Version``

### Handling Errors

Every error this library raises on its own is a ``RainmakerError``.
The notes features map the statuses the notes app answers with onto dedicated cases, such as ``RainmakerError/readOnly``, ``RainmakerError/locked``, ``RainmakerError/insufficientStorage`` and ``RainmakerError/noteConflict(current:)``, but only when the response actually comes from that app, while anything a proxy or the server answers on its behalf stays ``RainmakerError/unexpectedStatus(code:)``.

- ``RainmakerError``

### Building Custom Requests

If the built in features of Rainmaker do not suffice for your use case, you can use the following methods to build your own on top.
This is useful for API endpoints not covered by Rainmaker.
In example a third-party Nextcloud server app.
The names and values of query items are passed as they are and percent-encoded by the factories, including `+`, `&`, `=` and `#`, so a value such as `a+b` reaches the server as `a+b` rather than as `a b`.

- ``Server/makeAppRequest(for:method:queryItems:)``
- ``Server/makeOCSRequest(for:method:queryItems:)``
- ``Server/makeWebDAVRequest(for:method:)``
- ``Method``

### Customizing Transport

Both request factories above return a plain `URLRequest`, and a ``Server`` performs it through the abstractions below rather than through `URLSession` directly. Supplying your own implementations is how requests are intercepted, recorded or replayed, which is exactly what this package's own test suite does. The HTTP and the WebSocket sides are separate because a `URLSession` typed as ``Requesting`` does not expose its WebSocket features.

- ``Requesting``
- ``WebSocketConnecting``
- ``WebSocketChannel``
- ``WebSocketFrame``
