#  AGENTS.md

The human readable introduction of this Swift Package is in [README.md](README.md).

## Repository Structure

- `Sources/` contains the Swift source code per target.
- `Sources/Rainmaker/` contains the Swift source code for the main static library provided by this package.
- `Sources/Rainmaker/Bodies` contains static HTTP bodies for requests sent to a Nextcloud server. For example the uniform XML document when retrieving information about a WebDAV resource from the server. The reasoning is simplicity by having a plain file, ease of maintenance by making it editable like a standard XML document and performance by not always assembling it programmatically.
- `Sources/Rainmaker/Extensions/` is for implementations of extensions of first-party or platform types. One source code file per extended type and added feature.
- `Sources/Rainmaker/Models` contains Swift source code for data models which are also publicly available types. They do not necessarily mirror the structure and types as returned by the server in responses. They are meant to be as elegant and plausible as possible from a Swift client developer perspective, not necessarily mirroring the server responses exactly.
- `Sources/Rainmaker/Models/Responses` contains Swift source code for data models which actually enable the use of Swift's `Decodable` for server response data. They are not meant to be exposed outside the Swift package module but only as an intermediate representation to simplify deserialization.
- `Sources/RainmakerCLI/` contains the Swift source code for the accompanying command line utility which enables the usage of the library in a terminal environment without any additional upstream project.
- `Sources/Rainmaker/Documentation.docc/` is a DocC documentation catalog to provide additional documentation the one automatically derived from source code comments and symbol documentation in Swift source code. This is the place for documentation articles targeting developers which are using this library and package.
- `Tests/` contains the automated tests per target.
- `Tests/RainmakerTests/Responses/` contains static test fixtures which are the HTTP response bodies of actual server responses. They either are in JSON or XML format.
- `Rainmaker.png` and `Rainmaker.pxd` are static artwork files for presentation on the web and can be ignored.

## Code Style

- This project is set up to use SwiftFormat.
- The `Package.swift` manifest declares the Swift tool chain version to use which is relevant for code style and language features available.

## Testing Instructions

- Run `swift test` in the repository root directory.

## Pull Request Instructions

- Always run `swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore` before committing.
