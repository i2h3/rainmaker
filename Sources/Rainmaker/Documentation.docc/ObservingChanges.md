# Observing Changes

Observe server-side changes through a single stream of hints about what to retrieve again.

## Overview

The stream uses the `notify_push` WebSocket when the server offers it and falls back to polling otherwise.
The ``ServerEventTransport/polling`` transport polls only and never opens a socket, and watchOS always polls.

## Topics

### Streaming Events

- ``Server/events(_:)``
- ``Server/events(_:pollInterval:)``
- ``ServerEventOptions``
- ``ServerEventTransport``

### Events

- ``ServerEvent``
- ``ServerSubject``
