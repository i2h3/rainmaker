<div align="center">
    <img src="Rainmaker.png" alt="Logo of Rainmaker" width="256" height="256" />
</div>

# Rainmaker

[![Tests](https://github.com/i2h3/rainmaker/actions/workflows/test.yml/badge.svg)](https://github.com/i2h3/rainmaker/actions/workflows/test.yml)

A simple Swift library and CLI to access [Nextcloud](https://www.nextcloud.com) files programmatically.
This intentionally sticks to the basics and does not attempt to cover all the Nextcloud features.
It is stateless and is built using first-party frameworks like Foundation.
For the simplest use cases, you might prefer this over [NextcloudKit](https://github.com/nextcloud/NextcloudKit).

## Supported Platforms

* **iOS** 26 and newer
* **macOS** 26 and newer
* **tvOS** 26 and newer
* **visionOS** 26 and newer
* **watchOS** 26 and newer

## CLI Example

This package provides a command-line executable to expose the library in a shell environment.
You can clone this repository and run the following command in a Terminal to get further information.

```bash
$ swift run rainmaker help
```

### Using Command-Line Options

You can provide credentials directly as command-line options:

```bash
$ swift run RainmakerCLI list --host "https://cloud.example.com" --user "myuser" --password "mypassword"
```

### Using Environment Variables

To avoid password leakage and enable a default account pattern, you can set credentials via environment variables:

```bash
export RAINMAKER_HOST="https://cloud.example.com"
export RAINMAKER_USER="myuser"
export RAINMAKER_PASSWORD="mypassword"

$ swift run RainmakerCLI list
```

Environment variables can be mixed with command-line options. Command-line options take precedence over environment variables.

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

## Contributing

### Code Style

[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) was introduced into this project.
Before submitting a pull request, please ensure that your code changes comply with the currently configured code style.
You can run the following command in the root of the package repository clone:

```bash
swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore
```

Also, there is a GitHub action run automatically which lints code changes in pull requests.