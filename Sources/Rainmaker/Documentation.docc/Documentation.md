# ``Rainmaker``

A simple Swift library to interact with Nextcloud programmatically.

## Overview

Rainmaker intentionally sticks to the basics and does not attempt to cover all the Nextcloud features.
It is stateless and is built using first-party frameworks like Foundation.
For the simplest use cases, you might prefer this over [NextcloudKit](https://github.com/nextcloud/NextcloudKit).

Every feature is a method of ``Server``, which needs nothing but the address of the server and, for most features, the credentials of an account.
The articles below group those methods by the feature they belong to, together with the types they return.

## Installation

Add this repository to your Xcode project package dependencies or to your Swift package dependencies in the package manifest.
This is the only method currently supported.

## Topics

### Essentials

- ``Server``
- <doc:CommandLineInterface>

### Features

- <doc:ManagingFiles>
- <doc:Authenticating>
- <doc:Users>
- <doc:DiscoveringServerFeatures>
- <doc:ObservingChanges>
- <doc:ActivityStream>
- <doc:UserNotifications>
- <doc:WorkingWithNotes>
- <doc:WorkingWithTalk>
- <doc:Collectives>

### Errors

Every error this library raises on its own is a ``RainmakerError``, and the article of each feature says which of its cases that feature reports.

- ``RainmakerError``

### Extending Rainmaker

- <doc:CustomRequests>
