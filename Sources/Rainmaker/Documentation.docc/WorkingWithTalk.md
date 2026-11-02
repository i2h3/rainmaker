# Talk

Retrieve the conversations of an account, start a one-to-one conversation with another user, and send text and files into a conversation.

## Overview

These calls are what a client such as a share extension or a single action of Shortcuts needs to hand content over to Talk without being a Talk client itself.
Reading the messages of a conversation, calling and moderating are out of scope.
The Talk app is not part of a Nextcloud installation, and whether it is available is advertised through the ``Talk`` capability, which, unlike the ``Notes``, ``Notifications`` and ``Activity`` capabilities, is visible to anonymous clients as well.

### Listing Conversations

Conversations come back in the server's own order, which is no order at all, so a client presenting a list sorts them by ``Conversation/lastActivity`` itself.
The image of a conversation is whatever the server resolved it to, from an uploaded picture to an icon it generated, and is commonly an SVG document rather than a bitmap.
Each explicit avatar fetch bypasses the local HTTP cache.
Cache images between displays, refreshing when ``Conversation/avatarVersion`` changes and periodically even if it does not, for example once a day.
In one-to-one conversations that version says nothing at all: it is the same value for every such conversation and never moves when the other person changes their profile picture.
Keep separate cached images for each server, account, conversation token and appearance.

### Sending

The conversation with a person is found by searching the users with ``Server/searchUsers(_:)`` and passing the identifier of the chosen one to ``Server/createConversation(with:)``, which returns the one-to-one conversation that already exists rather than creating a second one, so calling it before every sending is safe.
Messages and files are sent as the authenticated account into the conversation a ``Conversation/token`` addresses, and none of these calls keeps any state between two of them.
Sending a file requires Talk 24 or later with its folders per conversation enabled, which ``Talk/storesAttachmentsPerConversation`` tells in advance, and the file is uploaded into the account's files first, where it stays and counts towards the account's quota.

### Errors

A missing Talk app, an unknown conversation and, when sending a file, a release older than Talk 24 are all reported as ``RainmakerError/notFound``, because the server answers each of them the same way, while a conversation the account may not write to is reported as ``RainmakerError/readOnly``.

## Topics

### Listing Conversations

- ``Server/conversations()``
- ``Server/conversationAvatar(_:darkTheme:)``
- ``Conversation``
- ``ConversationType``
- ``ConversationAvatar``

### Sending

- ``Server/createConversation(with:)``
- ``Server/sendMessage(_:toConversation:)``
- ``Server/sendFile(_:toConversation:caption:)``
