# Custom Requests and Transport

Build requests for endpoints Rainmaker does not cover, and supply your own transport to intercept, record or replay requests.

## Overview

If the built in features of Rainmaker do not suffice for your use case, the request factories of ``Server`` build your own requests on top, for example for the API of a third-party Nextcloud server app.
The names and values of query items are passed as they are and percent-encoded by the factories, including `+`, `&`, `=` and `#`, so a value such as `a+b` reaches the server as `a+b` rather than as `a b`.

The factories return a plain `URLRequest`, and a ``Server`` performs it through the abstractions below rather than through `URLSession` directly.
Supplying your own implementations is how requests are intercepted, recorded or replayed, which is exactly what this package's own test suite does.
The HTTP and the WebSocket sides are separate because a `URLSession` typed as ``Requesting`` does not expose its WebSocket features.

## Topics

### Building Requests

- ``Server/makeAppRequest(for:method:queryItems:)``
- ``Server/makeOCSRequest(for:method:queryItems:)``
- ``Server/makeWebDAVRequest(for:method:)``
- ``Method``

### Customizing Transport

- ``Requesting``
- ``WebSocketConnecting``
- ``WebSocketChannel``
- ``WebSocketFrame``
