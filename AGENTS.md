#  AGENTS.md

The human readable introduction of this Swift Package is in [README.md](README.md).

## Repository Structure

- `Sources/` contains the Swift source code per target.
- `Sources/Rainmaker/` contains the Swift source code for the main static library provided by this package.
- `Sources/Rainmaker/Requests/Bodies` contains static HTTP bodies for requests sent to a Nextcloud server. For example the uniform XML document when retrieving information about a WebDAV resource from the server. The reasoning is simplicity by having a plain file, ease of maintenance by making it editable like a standard XML document and performance by not always assembling it programmatically.
- `Sources/Rainmaker/Extensions/` is for implementations of extensions of first-party or platform types. One source code file per extended type and added feature.
- `Sources/Rainmaker/Models` contains Swift source code for data models which are also publicly available types. They do not necessarily mirror the structure and types as returned by the server in responses. They are meant to be as elegant and plausible as possible from a Swift client developer perspective, not necessarily mirroring the server responses exactly.
- `Sources/Rainmaker/Responses/Models` contains Swift source code for data models which actually enable the use of Swift's `Decodable` for server response data. They are not meant to be exposed outside the Swift package module but only as an intermediate representation to simplify deserialization.
- `Sources/Rainmaker/Push/` contains the `notify_push` WebSocket transport and the coordinator behind `Server.events(_:)`, which prefers the WebSocket when the server advertises the capability and falls back to polling otherwise. The mockable WebSocket abstraction protocols (`WebSocketConnecting`, `WebSocketChannel`, `WebSocketFrame`) live alongside `Requesting` in `Sources/Rainmaker/Requests/`, mirroring how the HTTP session is abstracted.
- `Sources/RainmakerCLI/` contains the Swift source code for the accompanying command line utility which enables the usage of the library in a terminal environment without any additional upstream project.
- `Sources/RainmakerCLI/Commands/RecordFixtures.swift` and `Sources/RainmakerCLI/Fixtures/` implement the `record-fixtures` subcommand which automates the creation of test fixtures. It is macOS-only: it deploys ephemeral Nextcloud containers via the `NextcloudContainerManager` package, runs the test suite against them in recording mode to capture real responses into `Tests/RainmakerTests/Responses/`, and verifies the captures replay without a server. Containers are deployed with the apps a suite's fixtures depend on but which are not part of a Nextcloud installation, currently the notes app, which makes a recording run depend on the app store being reachable. All of its Docker-facing code is guarded with `#if os(macOS)` so the simulator builds compile the CLI without it.
- `Sources/RainmakerTestServerTags/` is a small internal module holding `ServerVersion`, the single source of truth for the supported Nextcloud versions. Both the test target and the CLI's fixture recorder depend on it, so the version list is declared once.
- `Sources/Rainmaker/Documentation.docc/` is a DocC documentation catalog to provide additional documentation the one automatically derived from source code comments and symbol documentation in Swift source code. This is the place for documentation articles targeting developers which are using this library and package.
- `Tests/` contains the automated tests per target.
- `Tests/RainmakerTests/Responses/` contains static test fixtures which are the HTTP response bodies of actual server responses. They either are in JSON or XML format.
- `Tests/RainmakerTests/URLTestSession.swift` replays those fixtures during normal test runs, while `Tests/RainmakerTests/URLRecordingSession.swift` is its recording counterpart used by the `record-fixtures` subcommand. Both derive fixture paths through the shared `Tests/RainmakerTests/FixtureLocator.swift` so recording and replay can never diverge, and `Tests/RainmakerTests/FixtureCanonicalizer.swift` normalizes recorded responses (canonical host, redacted volatile fields) so fixtures stay stable. `Tests/RainmakerTests/ServerTesting.swift` selects between the two sessions based on the `RAINMAKER_FIXTURE_RECORD` environment variable.
- The `Server.events(_:)` tests do not use fixtures: they drive hand-authored WebSocket and request doubles (`Tests/RainmakerTests/MockWebSocketConnecting.swift`, `MockWebSocketChannel.swift`, `MockRequesting.swift`) so the WebSocket handshake, frame mapping, polling fallback, and reconnection are exercised deterministically without a server.
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
- Tests never contact a live server: they replay the static fixtures in `Tests/RainmakerTests/Responses/`. This keeps them fast and runnable on every platform and in continuous integration without Docker.

## Regenerating Test Fixtures

- The fixtures are regenerated by the `record-fixtures` subcommand of `rainmaker-cli`, which requires macOS and a running Docker daemon. It is never run in continuous integration.
- Run `swift run rainmaker-cli record-fixtures` to record every supported version, or scope it, e.g. `swift run rainmaker-cli record-fixtures --version 32.0.3 --filter ListingTests`.
- The subcommand deploys a Nextcloud container per version, provisions a baseline, records each test against it (writing into `Tests/RainmakerTests/Responses/`), and finally replays the captures with `swift test` to prove they work without a server. Review the result with `git diff` before committing.
- A handful of tests assume a server state different from the baseline. Those preconditions live in `FixtureProvisioner.applyPrecondition(forTest:)`. When the verification pass reports a test failing after recording, add or adjust its precondition there.
- Adding a server version is a single edit: add a case to `ServerVersion` in the `RainmakerTestServerTags` module. Both the test parameterization and the recorder's default version list derive from it (or pass `--version` to scope a run).

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
