<!--
SPDX-FileCopyrightText: 2025 Iva Horn
SPDX-License-Identifier: MIT
-->

# ``Rainmaker``

A simple Swift library to interact with Nextcloud programmatically.

## Example

Running the following code against a local [Nextcloud Docker container](https://hub.docker.com/_/nextcloud) with the default files in the user's root directory:

```swift
import Rainmaker

let server = Server(address: URL(string: "http://localhost:8080")!, password: "admin", user: "admin")
let items = try await server.content(at: "/")

for item in items {
    print(item.name)
}
```

Will print this output:

```plaintext
Documents
Nextcloud Manual.pdf
Nextcloud intro.mp4
Nextcloud.png
Photos
Readme.md
Reasons to use Nextcloud.pdf
Templates
Templates credits.md
```

## Topics

### Services

- ``Requesting``
- ``Server``
- ``Serving``

### Data Models

- ``Item``
- ``Lock``
- ``Permission``
- ``User``
