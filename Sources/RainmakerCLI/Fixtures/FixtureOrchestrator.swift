// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

#if os(macOS)
    import Foundation
    import NextcloudContainerManager
    import Rainmaker
    import RainmakerTestServerTags

    ///
    /// Drives the end-to-end fixture recording: deploying a container per server version, provisioning it, recording each test against it, and finally verifying the captures replay without a server.
    ///
    struct FixtureOrchestrator {
        ///
        /// The server versions recorded when none are given explicitly.
        ///
        /// Derived from the shared ``ServerVersion`` so the list is never duplicated: adding a version is a single edit there. The tool process leaves `RAINMAKER_FIXTURE_VERSION` unset, so every supported version is returned.
        ///
        static var defaultVersions: [String] {
            ServerVersion.allCases.map(\.rawValue)
        }

        ///
        /// The test suites whose tests issue live requests against the deployed container and therefore produce fixtures by recording.
        ///
        /// Excluded are suites that never touch the network (request-factory and fixture self-tests) and those whose fixtures are hand-authored with synthetic, version-independent values that a live server cannot reproduce: `TrashTests` (asserts fixed trash identifiers and deletion timestamps) and `PollTests` (a successful poll needs a completed browser flow, and it targets the canonical address rather than the container). Those are carried forward across versions instead.
        ///
        static let recordableSuites: Set<String> = [
            "CapabilitiesTests",
            "CreateDirectoryTests",
            "DeleteTests",
            "DownloadTests",
            "InfoTests",
            "ListingTests",
            "LoginTests",
            "MoveTests",
            "NavigationTests",
            "UploadTests",
        ]

        ///
        /// Apps disabled on every deployed container to keep responses deterministic and to make ``NextcloudContainerManager/deploy(configuration:)`` wait until the instance is ready.
        ///
        static let disabledApps = [
            "bruteforcesettings",
            // Disabling the dashboard makes "files" the user's default app (the default `defaultapp` order is "dashboard,files"), which `NavigationTests` asserts on.
            "dashboard",
            "firstrunwizard",
            "nextcloud_announcements",
            "password_policy",
        ]

        ///
        /// The root of the Swift package, used as the working directory for the spawned `swift` invocations.
        ///
        let packageDirectory: URL

        ///
        /// When set, only tests whose identifier contains this substring are recorded.
        ///
        let filter: String?

        ///
        /// Whether to leave the container running after recording instead of tearing it down.
        ///
        let keepRunning: Bool

        ///
        /// Whether to provision and reset the baseline data, which can be skipped for server-only suites.
        ///
        let provisionBaseline: Bool

        ///
        /// Record the given server versions and, unless disabled, verify the captures afterwards.
        ///
        func record(versions: [String], verify: Bool) async throws {
            let tests = try recordableTests()
            log("Recording \(tests.count) test(s) across \(versions.count) version(s): \(versions.joined(separator: ", "))")

            for version in versions {
                try await record(version: version, tests: tests)
            }

            guard verify else {
                log("Skipping verification. Run `swift test` to validate the recorded fixtures.")
                return
            }

            log("Verifying recorded fixtures by replaying them without a server…")
            let status = try runSwift(["test"], environment: cleanEnvironment, streamingOutput: true)

            guard status == 0 else {
                throw FixtureRecordingError.verificationFailed
            }

            log("Verification passed.")
        }

        // MARK: - Private

        ///
        /// Record all tests against a freshly deployed container for a single version.
        ///
        private func record(version: String, tests: [String]) async throws {
            log("Deploying nextcloud:\(version)…")
            let container = try await NextcloudContainerManager.deploy(configuration: NextcloudConfiguration(tag: version, disabledApps: Self.disabledApps))
            log("Container ready at http://localhost:\(container.port) (id \(container.id.prefix(12))).")

            do {
                let address = URL(string: "http://localhost:\(container.port)/")!
                let server = Server(address: address, password: "admin", user: "admin", userAgent: "RainmakerFixtures")
                let baselineDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("rainmaker-baseline-\(version)")
                let provisioner = FixtureProvisioner(server: server, baselineDirectory: baselineDirectory)

                if provisionBaseline {
                    log("Provisioning baseline data…")
                    try await provisioner.provision()
                }

                for test in tests {
                    if provisionBaseline {
                        try await provisioner.reset()
                        try await provisioner.applyPrecondition(forTest: test)
                    }

                    log("Recording \(version) → \(test)…")
                    let status = try runSwift(["test", "--no-parallel", "--filter", regexEscaped(test)], environment: recordingEnvironment(version: version, port: container.port), streamingOutput: false)

                    // A failing assertion during recording is surfaced but does not abort the run: the fixture was written before the assertion and the discrepancy is informative.
                    if status != 0 {
                        log("⚠️  \(test) did not pass against the live server (exit \(status)). The fixture was still captured; review it.")
                    }
                }
            } catch {
                try? await NextcloudContainerManager.delete(container.id)
                throw error
            }

            if keepRunning {
                log("Leaving container running at http://localhost:\(container.port) (id \(container.id.prefix(12))).")
            } else {
                log("Tearing down container…")
                try await NextcloudContainerManager.delete(container.id)
            }
        }

        ///
        /// Enumerate the recordable test identifiers via `swift test list`, filtered to the network suites and any `--filter` substring.
        ///
        /// Identifiers are returned in the `Suite/method` form which is both a valid `--filter` argument and stable across server versions.
        ///
        private func recordableTests() throws -> [String] {
            let output = try captureSwift(["test", "list"])

            return output
                .split(separator: "\n")
                .map(String.init)
                .compactMap { line -> String? in
                    // Lines look like "RainmakerTests.DeleteTests/file(_:)".
                    guard let slash = line.firstIndex(of: "/") else {
                        return nil
                    }

                    let suite = String(line[..<slash].split(separator: ".").last ?? "")

                    guard Self.recordableSuites.contains(suite) else {
                        return nil
                    }

                    let method = String(line[line.index(after: slash)...].prefix { $0 != "(" })
                    let identifier = "\(suite)/\(method)"

                    if let filter, identifier.contains(filter) == false {
                        return nil
                    }

                    return identifier
                }
        }

        ///
        /// The process environment for a recording run, layering the recording variables over the inherited environment.
        ///
        private func recordingEnvironment(version: String, port: UInt) -> [String: String] {
            var environment = ProcessInfo.processInfo.environment
            environment["RAINMAKER_FIXTURE_RECORD"] = "1"
            environment["RAINMAKER_FIXTURE_SERVER"] = "http://localhost:\(port)/"
            environment["RAINMAKER_FIXTURE_VERSION"] = version
            return environment
        }

        ///
        /// The inherited environment with any recording variables removed, used for enumeration and verification so they replay instead of record.
        ///
        private var cleanEnvironment: [String: String] {
            var environment = ProcessInfo.processInfo.environment
            environment["RAINMAKER_FIXTURE_RECORD"] = nil
            environment["RAINMAKER_FIXTURE_SERVER"] = nil
            environment["RAINMAKER_FIXTURE_VERSION"] = nil
            return environment
        }

        ///
        /// Escape regular-expression metacharacters so a test identifier can be passed verbatim to `swift test --filter`.
        ///
        private func regexEscaped(_ identifier: String) -> String {
            let metacharacters = Set("\\.^$|?*+()[]{}")
            return String(identifier.flatMap { metacharacters.contains($0) ? ["\\", $0] : [$0] })
        }

        ///
        /// Run `swift` with the given arguments and return the exit status, optionally streaming its output to the console.
        ///
        @discardableResult
        private func runSwift(_ arguments: [String], environment: [String: String], streamingOutput: Bool) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swift"] + arguments
            process.currentDirectoryURL = packageDirectory
            process.environment = environment

            if streamingOutput == false {
                // Quiet recording runs keep the progress log readable; failures are reported by exit status.
                process.standardOutput = FileHandle.nullDevice
            }

            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        ///
        /// Run `swift` with the given arguments and return its captured standard output.
        ///
        private func captureSwift(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swift"] + arguments
            process.currentDirectoryURL = packageDirectory
            process.environment = cleanEnvironment

            let pipe = Pipe()
            process.standardOutput = pipe

            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return String(data: data, encoding: .utf8) ?? ""
        }

        ///
        /// Emit a progress line to standard error so it is not mixed into captured output.
        ///
        private func log(_ message: String) {
            FileHandle.standardError.write(Data("[record-fixtures] \(message)\n".utf8))
        }
    }
#endif
