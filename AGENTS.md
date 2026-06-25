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
- Every type declarations must reside in its own source code file.
- Every type declaration must have a documentation comment.
- Every property declaration must have a documentation comment.
- Documentation comments should also explain how the documented type or property relates to other symbols in the project.
- Documentation comments should have one empty line at their top and their bottom each.
- Documentation comments must not wrap at a fixed column count but when a sentence is finished. Line lengths do not matter in documentation comments. A full sentence should always be written into a single line.
- Never wrap arguments in func declarations or calls.
- Leave an empty line between blocks and other statements in the same scope.
- Always run `swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore` after applying changes.

## Testing Instructions

- Run `swift test` in the repository root directory.

## Documentation Instructions

- Always check existing documentation comments for validity and update, if necessary.
- Whenever the files and folders within the repository change, update the "Repository Structure" section of this document accordingly.
- Always check the `./README.md` for validity and update, if necessary.
- Semantic versioning is used. Report on the impact in this regard after applying changes.

## Commit Instructions

- Never commit automatically.
- Suggest commit title and description.
- If the changes relate to a specific issue, mention the issue number in the title.

## Pull Request Instructions

- Never open a pull request automatically.
- Suggest a concise pull request description.
- If the changes relate to a specific issue, mention the issue number in the title.
