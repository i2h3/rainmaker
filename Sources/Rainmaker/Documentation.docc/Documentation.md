# ``Rainmaker``

A simple Swift library to interact with Nextcloud programmatically.

## Overview

Rainmaker intentionally sticks to the basics and does not attempt to cover all the Nextcloud features.
It is stateless and is built using first-party frameworks like Foundation.
For the simplest use cases, you might prefer this over [NextcloudKit](https://github.com/nextcloud/NextcloudKit).

Rainmaker supports these platforms:

* **iOS** 26 and newer
* **macOS** 26 and newer
* **tvOS** 26 and newer
* **visionOS** 26 and newer
* **watchOS** 26 and newer

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
- ``User``

### Handling Errors

- ``RainmakerError``
