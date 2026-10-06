#  AGENTS.md

The human readable introduction of this Swift Package is in [README.md](README.md).

## Repository Structure

- `Sources/` contains the Swift source code per target.
- `Sources/Rainmaker/` contains the Swift source code for the main static library provided by this package.
- `Sources/Rainmaker/Server.swift` declares `Server` with the files, OCS and app features, while `Sources/Rainmaker/Server+Events.swift` and `Sources/Rainmaker/Server+Notes.swift` extend it with the event stream and the notes features respectively. The notes extension also holds the private helpers every notes feature is built on: the request factory for the notes API roots (`Server.notesAPIRoot`, and `Server.notesAttachmentAPIRoot` because older notes releases route attachments only below `v1.4`), the mapping of the notes app's statuses onto `RainmakerError` gated by its `X-Notes-API-Versions` header (read through `Extensions/HTTPURLResponse+notesAPIVersions.swift`), and the JSON decoding and encoding of payloads. The listing of changed notes reads its `Last-Modified`, `ETag` and chunk headers into `NoteChanges` through `Extensions/Date+httpDate.swift` and `Extensions/String+entityTag.swift`, the latter also quoting the entity tag a conditional request sends in `If-None-Match`.
- `Sources/Rainmaker/Requests/Bodies` contains static HTTP bodies for requests sent to a Nextcloud server. For example the uniform XML document when retrieving information about a WebDAV resource from the server. The reasoning is simplicity by having a plain file, ease of maintenance by making it editable like a standard XML document and performance by not always assembling it programmatically.
- `Sources/Rainmaker/Extensions/` is for implementations of extensions of first-party or platform types. One source code file per extended type and added feature.
- `Sources/Rainmaker/Models` contains Swift source code for data models which are also publicly available types. They do not necessarily mirror the structure and types as returned by the server in responses. They are meant to be as elegant and plausible as possible from a Swift client developer perspective, not necessarily mirroring the server responses exactly. Models a downstream project may want to fake, such as `Note` and `NotesSettings`, offer a public memberwise initializer. The `Notes` capability also compares releases of the notes app (`Notes.isAppVersion(atLeast:)`), because some of its behaviours, like where uploaded attachments land, are tied to a release rather than to the notes API version; `Tests/RainmakerTests/NotesCapabilityVersionTests.swift` covers that comparison.
- `Sources/Rainmaker/Responses/Models` contains Swift source code for data models which actually enable the use of Swift's `Decodable` for server response data. They are not meant to be exposed outside the Swift package module but only as an intermediate representation to simplify deserialization.
- `Sources/Rainmaker/Push/` contains the `notify_push` WebSocket transport and the coordinator behind `Server.events(_:)`, which prefers the WebSocket when the server advertises the capability and falls back to polling otherwise. The mockable WebSocket abstraction protocols (`WebSocketConnecting`, `WebSocketChannel`, `WebSocketFrame`) live alongside `Requesting` in `Sources/Rainmaker/Requests/`, mirroring how the HTTP session is abstracted. `PendingPing` (with its `PendingPingState`) is what `URLSessionWebSocketChannel.sendPing()` waits through: it resumes the waiting task exactly once, because `URLSessionWebSocketTask.sendPing(pongReceiveHandler:)` has been seen calling its handler more than once for one ping, concurrently, when a connection is torn down, and also never calling it at all, which is why the waiting task's cancellation competes for the same outcome. Neither URLSession's `receive()` nor its pong handler observes task cancellation, so `PushNotificationsConnection` ends a session by closing its channel rather than by cancelling its tasks, and bounds every ping with a pong timeout.
- `Sources/RainmakerCLI/` contains the Swift source code for the accompanying command line utility which enables the usage of the library in a terminal environment without any additional upstream project.
- `Sources/RainmakerCLI/Commands/RecordFixtures.swift` and `Sources/RainmakerCLI/Fixtures/` implement the `record-fixtures` subcommand which automates the creation of test fixtures. It is macOS-only: it deploys ephemeral Nextcloud containers via the `NextcloudContainerManager` package, runs the test suite against them in recording mode to capture real responses into `Tests/RainmakerTests/Responses/`, and verifies the captures replay without a server. Containers are deployed with the apps a suite's fixtures depend on but which are not part of a Nextcloud installation, currently the notes app and the Talk app, which makes a recording run depend on the app store being reachable. All of its Docker-facing code is guarded with `#if os(macOS)` so the simulator builds compile the CLI without it.
- `Sources/RainmakerTestServerTags/` is a small internal module holding `ServerVersion`, the single source of truth for the supported Nextcloud versions. Both the test target and the CLI's fixture recorder depend on it, so the version list is declared once.
- `Sources/Rainmaker/Documentation.docc/` is a DocC documentation catalog to provide additional documentation the one automatically derived from source code comments and symbol documentation in Swift source code. This is the place for documentation articles targeting developers which are using this library and package.
- `Tests/` contains the automated tests per target.
- `Tests/RainmakerTests/Responses/` contains static test fixtures which are the HTTP response bodies of actual server responses. They either are in JSON or XML format.
- `Tests/RainmakerTests/URLTestSession.swift` replays those fixtures during normal test runs, while `Tests/RainmakerTests/URLRecordingSession.swift` is its recording counterpart used by the `record-fixtures` subcommand. Both derive fixture paths through the shared `Tests/RainmakerTests/FixtureLocator.swift` so recording and replay can never diverge, and `Tests/RainmakerTests/FixtureCanonicalizer.swift` normalizes recorded responses (canonical host, redacted volatile fields) so fixtures stay stable. Like its body rules, the response header fields it keeps depend on the request path: responses of the notes app additionally keep `ETag`, `Last-Modified`, `X-Notes-Chunk-Cursor` (all three with fixed canonical values) and `X-Notes-Chunk-Pending`, which every other response drops. `Tests/RainmakerTests/NoteChangesRequestTests.swift` covers reading those headers and the conditional request with `MockRequesting`, because a replayed fixture neither carries live header values nor proves which request headers were sent, while `EntityTagTests.swift` and `HTTPDateTests.swift` cover the two conversions. `Tests/RainmakerTests/ServerTesting.swift` selects between the two sessions based on the `RAINMAKER_FIXTURE_RECORD` environment variable.
- The `Server.events(_:)` tests do not use fixtures: they drive hand-authored WebSocket and request doubles (`Tests/RainmakerTests/MockWebSocketConnecting.swift`, `MockWebSocketChannel.swift`, `MockRequesting.swift`) so the WebSocket handshake, frame mapping, polling fallback, reconnection, and teardown are exercised deterministically without a server. `MockPingBehavior` scripts whether a mock channel answers pings, and `MockWebSocketClosure` records that a channel was closed and lets its receiving ignore task cancellation until then, as `URLSessionWebSocketTask` does, so the teardown is tested against the behaviour it actually has to cope with.
- `Tests/RainmakerTests/PendingPingTests.swift` drives `PendingPing` directly, a `URLSessionWebSocketTask` being impossible to substitute: it stores the pong handler a ping hands out and calls it the way the framework has been seen to, later, repeatedly, concurrently, or never. `Eventually.swift` is the polling wait those tests and the teardown tests use instead of `WithTimeout.swift`, which cannot bound an operation that ignores cancellation, and `LockedValue.swift` is the lock-protected box they share state with `@Sendable` closures through.
- `Rainmaker.png` is a static artwork file for presentation on the web and can be ignored.

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
- Run `swift run rainmaker-cli record-fixtures` to record every supported version, or scope it, e.g. `swift run rainmaker-cli record-fixtures --version 32.0.11 --filter ListingTests`.
- The subcommand deploys a Nextcloud container per version, provisions a baseline, records each test against it (writing into `Tests/RainmakerTests/Responses/`), and finally replays the captures with `swift test` to prove they work without a server. Review the result with `git diff` before committing.
- Two apps the fixtures depend on are not part of a Nextcloud installation and are installed into every container from the app store, declared as `FixtureOrchestrator.installedApps`: the notes app for `NotesTests` and the Talk app (`spreed`) for `ConversationsTests`. That is why the recorded capabilities and navigation fixtures advertise `notes` and `spreed`, and it means recording needs the app store to be reachable. It also means the fixtures of those two suites track a release of their app rather than of the server, which is why their assertions rest on state `FixtureProvisioner` seeds rather than on whatever the app creates by itself. The app store currently hands Nextcloud 31 and 32 the notes app 5.0.2 and Nextcloud 33 and newer the notes app 6.1.0. A test whose expectations differ between those releases records the capabilities alongside its own requests and branches on `Notes.isAppVersion(atLeast:)` rather than on the server version, as `NotesTests.settings` does.
- The chunked upload tests in `UploadTests` write files just above `Server.minimumChunkSize` (5 MiB), because the library raises smaller chunk sizes to it, and they pin the local modification date: the folder a chunked upload is staged in is named deterministically from the remote path, the size and the modification date of the file, which is what keeps its `MKCOL`, `PUT` and `MOVE` fixtures replayable.
- Fixtures of the notes app keep the headers `NoteChanges` is read from, with `ETag`, `Last-Modified` and `X-Notes-Chunk-Cursor` replaced by canonical values (see `FixtureCanonicalizer.notesHeaderFields`), so tests only assert that those values are present. Every recording of `NotesTests` also reassigns note identifiers and may reorder the listings. A test which sends the same method and path twice, such as a conditional request answered with `304 Not Modified` after a full one, cannot be served by the fixture tree, because `FixtureLocator` ignores query strings and request headers; such tests use `MockRequesting` instead.
- A handful of tests assume a server state different from the baseline. Those preconditions live in `FixtureProvisioner.applyPrecondition(forTest:)`. When the verification pass reports a test failing after recording, add or adjust its precondition there.
- Adding a server version is a single edit: add a case to `ServerVersion` in the `RainmakerTestServerTags` module. Both the test parameterization and the recorder's default version list derive from it (or pass `--version` to scope a run).

## Documentation Instructions

- Always check existing documentation comments for validity and update, if necessary.
- The published API reference is generated from public symbols only, so the full documentation of every `Server` method lives on the method itself in `Sources/Rainmaker/Server.swift`, `Sources/Rainmaker/Server+Events.swift` and `Sources/Rainmaker/Server+Notes.swift`. The internal `Serving` protocol carries one-line abstracts only.
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
