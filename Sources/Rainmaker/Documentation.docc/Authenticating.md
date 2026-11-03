# Authentication

Obtain an app password through the server's login flow and revoke it again once it is no longer needed.

## Overview

``Server/login()`` begins a login flow, which the user completes in a browser, while the client polls for its result.
``Server/poll(_:)`` returns `nil` while the user has not completed the flow and throws only for real failures, so a client polling it can tell an unreachable server from a pending flow, while the deprecated ``Server/poll(_:token:)`` throws in both cases.

## Topics

### Logging In

- ``Server/login()``
- ``Server/poll(_:)``
- ``Server/poll(_:token:)``
- ``LoginFlow``
- ``LoginResult``

### Logging Out

- ``Server/deleteAppPassword()``
