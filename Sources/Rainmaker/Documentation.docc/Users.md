# Users

Look up the account a server authenticates as, search other users and retrieve the pictures they are represented by.

## Overview

The identifier of an account is not necessarily the name it logs in with, because a server can accept an email address or a login attribute of an LDAP directory as the login name, which is what ``Server/user`` and ``LoginResult/name`` hold.
``User/id`` is the identifier the server keys the account by, and it is what ``Server/userAvatar(_:size:darkTheme:)`` and ``Server/createConversation(with:)`` expect.
The WebDAV paths of this library are still built from ``Server/user``, so they only work for accounts whose login name is their identifier.

``Server/searchUsers(_:)`` finds other users by name or identifier, for example to pick the person to start a Talk conversation with, as far as the sharing settings of the server let the account see them.

The server answers with a picture for every user it knows, drawing one from their initials when that user uploaded none, so an absent picture is not reported as an absent response.
``UserAvatar/isCustom`` is the only thing that distinguishes the two, and a client with a monogram style of its own has to consult it or it will draw over the server's placeholder rather than in place of it.
Only two sizes are served, which is what ``AvatarSize`` models: the endpoint rounds any other value to one of them.
Each fetch bypasses the local HTTP cache, and the endpoint publishes no version marker, so cache images on a bounded lifetime and key entries by server, account, user, size and appearance.

## Topics

### Accounts

- ``Server/currentUser()``
- ``Server/searchUsers(_:)``
- ``User``

### Avatars

- ``Server/userAvatar(_:size:darkTheme:)``
- ``UserAvatar``
- ``AvatarSize``
