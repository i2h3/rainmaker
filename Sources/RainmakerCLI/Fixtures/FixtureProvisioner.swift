// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

#if os(macOS)
    import Foundation
    import Rainmaker

    ///
    /// Establishes and restores the remote server state the test fixtures are recorded against.
    ///
    /// Rather than relying on the Nextcloud default skeleton, which differs between versions, the provisioner generates a controlled baseline tree on the local file system and uploads it. The very same local tree is reused to reset the server between recordings, and per-test preconditions adjust the few tests whose fixtures assume a state different from the baseline.
    ///
    struct FixtureProvisioner {
        ///
        /// The server to provision, pointing at the live container.
        ///
        let server: Server

        ///
        /// The local directory holding the generated baseline tree, reused as the reset source.
        ///
        let baselineDirectory: URL

        ///
        /// The special-character directory names exercised by the listing tests, each seeded with a `Readme.md`.
        ///
        static let specialCharacterNames = [":", "?", "&", "#", "%"]

        ///
        /// Generate the baseline tree on disk and upload it to the server.
        ///
        /// This is idempotent: the local tree is regenerated and uploaded with `force` so that an existing remote state is reconciled to the baseline.
        ///
        func provision() async throws {
            try generateBaselineTree()
            try await reset()
        }

        ///
        /// Reset the remote state to the baseline by reconciling it with the generated local tree.
        ///
        /// A forced directory upload removes remote items absent from the baseline and restores those which a previous recording mutated, so each test starts from an identical state.
        ///
        func reset() async throws {
            try await server.upload(baselineDirectory, to: "/", force: true)
        }

        ///
        /// Apply the precondition a specific test assumes before its requests are recorded.
        ///
        /// Most tests record correctly against the plain baseline. The few which assume a different state are adjusted here, keyed by the identifier `swift test list` prints. When the replay-verify pass reports a test failing after recording, its required precondition belongs here.
        ///
        func applyPrecondition(forTest testID: String) async throws {
            if testID.contains("UploadTests/overwriteDirectory") {
                // The fixture deletes a remote orphan, so "/Documents" must contain an extra file besides the baseline "Example.md".
                let orphan = baselineDirectory.appendingPathComponent("Orphan.txt")
                try Data("orphan".utf8).write(to: orphan)
                defer { try? FileManager.default.removeItem(at: orphan) }
                try await server.upload(orphan, to: "/Documents", force: true)
            } else if testID.contains("UploadTests/directory") {
                // The fixture creates "/Documents" fresh (MKCOL → 201), so it must be absent beforehand.
                try? await server.delete("/Documents")
            } else if testID.contains("MoveTests/overwriteExisting") || testID.contains("MoveTests/conflictWhenExists") {
                // Both move "/Readme.md" onto an existing "/Existing.md", so that destination must already be present.
                let existing = baselineDirectory.appendingPathComponent("Existing.md")
                try Data("# Existing\n".utf8).write(to: existing)
                defer { try? FileManager.default.removeItem(at: existing) }
                try await server.upload(existing, to: "/", force: true)
            }
        }

        // MARK: - Private

        ///
        /// Generate the controlled baseline tree on the local file system.
        ///
        /// The structure mirrors what the tests expect to find on the server: the top-level files and folders the listing, download, and upload tests reference, plus both the plain and the percent-encoded "Special Characters" folders with their special-character children.
        ///
        private func generateBaselineTree() throws {
            // Start from a clean tree so a previous run's contents never leak into the baseline.
            try? FileManager.default.removeItem(at: baselineDirectory)
            try FileManager.default.createDirectory(at: baselineDirectory, withIntermediateDirectories: true)

            try write("# Rainmaker\n", to: "Readme.md")
            try write("# Example\n", to: "Documents/Example.md")
            try write("frog", to: "Photos/Frog.jpg")
            try write("whiteboard", to: "Templates/Brainstorming.whiteboard")

            for folder in ["Special Characters", "Special%20Characters"] {
                for name in Self.specialCharacterNames {
                    try write("# Readme\n", to: "\(folder)/\(name)/Readme.md")
                }
            }
        }

        ///
        /// Write a UTF-8 string to a file at the given relative path inside the baseline directory, creating intermediate directories.
        ///
        private func write(_ contents: String, to relativePath: String) throws {
            let fileURL = baselineDirectory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: fileURL)
        }
    }
#endif
