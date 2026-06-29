// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

#if os(macOS)
    import ArgumentParser
    import Foundation

    ///
    /// Records test fixtures by running the test suite against ephemeral Nextcloud containers.
    ///
    /// This is a developer subcommand which automates the otherwise manual creation of the static fixtures in `Tests/RainmakerTests/Responses/`. It deploys a container per server version via the `NextcloudContainerManager` package, records the test suite against it, and verifies the captures replay without a server. It is available on macOS only, where Docker can be controlled, and is never run by continuous integration.
    ///
    struct RecordFixtures: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "record-fixtures", abstract: "Record test fixtures by deploying Nextcloud containers and running the test suite against them.")

        ///
        /// The server versions to record, given as Docker image tags. Repeatable. Defaults to every supported version.
        ///
        @Option(name: .customLong("version"), parsing: .singleValue, help: "Server version (Docker tag) to record. Repeatable. Defaults to all supported versions.")
        var versions: [String] = []

        ///
        /// Restricts recording to tests whose identifier contains this substring.
        ///
        @Option(help: "Only record tests whose identifier contains this substring, e.g. \"ListingTests\".")
        var filter: String?

        ///
        /// Leaves the container running after recording instead of tearing it down.
        ///
        @Flag(help: "Leave the container running after recording.")
        var keepRunning = false

        ///
        /// Skips the replay-verify pass.
        ///
        @Flag(help: "Skip the replay-verify pass that confirms fixtures work without a server.")
        var noVerify = false

        ///
        /// Skips provisioning and resetting the baseline data, useful when recording server-only suites.
        ///
        @Flag(help: "Skip provisioning baseline data (for server-only suites such as capabilities or login).")
        var noProvision = false

        ///
        /// The root of the Swift package. Defaults to the current working directory.
        ///
        @Option(help: "Path to the package root. Defaults to the current directory.")
        var packagePath: String?

        func run() async throws {
            let packageDirectory = URL(fileURLWithPath: packagePath ?? FileManager.default.currentDirectoryPath)
            let orchestrator = FixtureOrchestrator(packageDirectory: packageDirectory, filter: filter, keepRunning: keepRunning, provisionBaseline: noProvision == false)
            let versionList = versions.isEmpty ? FixtureOrchestrator.defaultVersions : versions

            try await orchestrator.record(versions: versionList, verify: noVerify == false)
        }
    }
#endif
