# Rainmaker

A simple Swift library to access [Nextcloud](https://www.nextcloud.com) files programmatically.
This intentionally sticks to the basics and does not attempt to cover all the Nextcloud features.
It is stateless and does not have any dependencies except first-party frameworks provided by the target platforms.
For the simplest use cases, you might prefer this over [NextcloudKit](https://github.com/nextcloud/NextcloudKit).

## CLI Example

This package provides a command-line executable to expose the library in a shell environment.
You can clone this repository and run the following command in a Terminal to get further information.

```bash
$ swift run rainmaker help
```

## Swift Library Example

Running the following code against [a local Nextcloud Docker container](https://hub.docker.com/_/nextcloud) with the default files in the user's root directory:

```swift
import Rainmaker

let server = Server(address: URL(string: "http://localhost:8081")!, password: "admin", user: "admin")
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

## Installation

Add this repository to your Xcode project package dependencies or to your Swift package dependencies.
This is the only method currently supported.

## Usage

- `import Rainmaker` to make use of the library in your Swift code.
- `import RainmakerMocks` to make use of the library mocks in your Swift tests.
