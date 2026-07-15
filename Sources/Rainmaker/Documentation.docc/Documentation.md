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
- ``NavigationItem``
- ``NotificationItem``
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

### Capabilities

- ``CapabilitySet``
- ``Capability``
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

- ``Server/makeOCSRequest(for:method:)``
- ``Server/makeWebDAVRequest(for:method:)``
