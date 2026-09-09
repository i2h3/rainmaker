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

- ``Server/enumerate(at:recursively:)->AsyncThrowingStream<Item,Error>``
- ``Server/enumerate(at:recursively:)->[Item]``
- ``Server/info(_:)``
- ``Server/download(_:to:force:)``
- ``Server/upload(_:to:force:)``
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

### Notes

Retrieve the notes of an account, either all of them at once or, for a client keeping its own copy, only those the server recorded a change for since a given moment.
Whether the app providing them is installed at all is advertised through the ``Notes`` capability, which matters more here than elsewhere because the notes app is not part of a Nextcloud installation, and which also reports whether it is new enough to be usable.
Notes are ordinary files, so ``NotesSettings`` says where to find them when reaching for them over WebDAV instead.

- ``Server/notes()``
- ``Server/notes(changedSince:)``
- ``Server/notesSettings()``
- ``Note``
- ``NoteChanges``
- ``NotesSettings``

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
- ``Notes``
- ``Notifications``
- ``PushNotifications``
- ``Talk``
- ``Theming``
- ``Trashing``
- ``Version``

### Handling Errors

- ``RainmakerError``

### Building Custom Requests

If the built in features of Rainmaker do not suffice for your use case, you can use the following methods to build your own on top.
This is useful for API endpoints not covered by Rainmaker.
In example a third-party Nextcloud server app.

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
