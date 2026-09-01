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

### Data Models

- ``AvailableQuota``
- ``Item``
- ``Lock``
- ``LoginFlow``
- ``LoginResult``
- ``Quota``
- ``Permission``
- ``TrashItem``
- ``User``

### Observing Changes

Observe server-side changes over the `notify_push` WebSocket when available, falling back to polling otherwise, through a single stream of re-fetch hints.

- ``Server/events(_:)``
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

### Apps Navigation

List the server apps, such as Files, Photos and Activity, which the server advertises to the authenticated user so that a client can surface them in its own navigation.

- ``Server/navigation()``
- ``NavigationItem``

### Capabilities

- ``CapabilitySet``
- ``Capability``
- ``Activity``
- ``Notifications``
- ``PushNotifications``
- ``Theming``
- ``Trashing``
- ``Version``

### Handling Errors

- ``RainmakerError``

### Building Custom Requests

If the built in features of Rainmaker do not suffice for your use case, you can use the following methods to build your own on top.
This is useful for API endpoints not covered by Rainmaker.
In example a third-party Nextcloud server app.

- ``Server/makeOCSRequest(for:method:queryItems:)``
- ``Server/makeWebDAVRequest(for:method:)``
- ``Method``

### Customizing Transport

Both request factories above return a plain `URLRequest`, and a ``Server`` performs it through the abstractions below rather than through `URLSession` directly. Supplying your own implementations is how requests are intercepted, recorded or replayed, which is exactly what this package's own test suite does. The HTTP and the WebSocket sides are separate because a `URLSession` typed as ``Requesting`` does not expose its WebSocket features.

- ``Requesting``
- ``WebSocketConnecting``
- ``WebSocketChannel``
- ``WebSocketFrame``
