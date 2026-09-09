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
        /// The folder inside the account the seeded notes are placed in, relative to its root.
        ///
        /// Looked up from the server by ``FixtureOrchestrator`` rather than assumed, because the notes app derives this from the account's locale and ignores notes anywhere else. See ``Server/notesSettings()``.
        ///
        let notesFolder: String

        ///
        /// The special-character directory names exercised by the listing tests, each seeded with a `Readme.md`.
        ///
        static let specialCharacterNames = [":", "?", "&", "#", "%"]

        ///
        /// The notes seeded into the account's notes folder, each with the modification date to stamp it with.
        ///
        /// The notes app derives a note from every file in that folder: its title from the file name, its category from the sub-folder and its content from the file. Seeding them as plain files therefore needs nothing beyond the WebDAV upload the baseline already uses.
        ///
        /// The modification dates are fixed rather than left at the upload time so that the `modified` field the notes API reports is reproducible across recordings, which is what lets `NotesTests` assert on it. ``Server/upload(_:to:force:)`` carries them to the server in the `X-OC-Mtime` header.
        ///
        static let notes: [(name: String, contents: String, modification: Date)] = [
            (name: "Rainmaker.md", contents: "# Rainmaker\n", modification: Date(timeIntervalSince1970: 1_700_000_000)),
            (name: "Recipes/Pancakes.md", contents: "# Pancakes\n", modification: Date(timeIntervalSince1970: 1_600_000_000)),
        ]

        ///
        /// The name of the Talk conversation seeded for `ConversationsTests`, which is what makes it findable without relying on a token or an identifier.
        ///
        /// A conversation with a known name is needed because a plain Talk installation only creates conversations of its own, whose names are localized to the account's language and whose unread counts follow the release of the app rather than of the server. The same literal appears in the test suite, which cannot import this module.
        ///
        static let seededConversation = "Rainmaker"

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
            } else if testID.contains("ConversationsTests/") {
                try await seedConversation()
            } else if testID.contains("NotesTests/fetchNone") {
                // The fixture records an account without a single note, so the seeded notes folder has to be gone beforehand. The baseline is restored before every following test, which brings it back.
                try? await server.delete("/\(notesFolder)")
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
        /// Create the Talk conversation named ``seededConversation`` unless it already exists.
        ///
        /// Conversations live outside the account's files, so ``reset()`` neither removes nor restores them and the one created here survives for the rest of the container's life. That is why this is idempotent and why every test of the suite asks for it rather than only the first: the recorder runs them in whichever order `swift test list` reports, so no test can rely on another having run before it.
        ///
        /// Talk has no WebDAV surface to provision through, so the request is built with ``Server/makeOCSRequest(for:method:queryItems:)`` and performed on a session of its own. That is the sanctioned route for reaching an endpoint the library itself does not cover.
        ///
        private func seedConversation() async throws {
            let existing = try await server.conversations()

            guard existing.contains(where: { $0.displayName == Self.seededConversation }) == false else {
                return
            }

            var request = try server.makeOCSRequest(for: "apps/spreed/api/v4/room", method: .post)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // A room type of 2 is a group conversation, which is the kind a client creates and therefore the kind worth recording.
            request.httpBody = try JSONSerialization.data(withJSONObject: ["roomType": 2, "roomName": Self.seededConversation])

            let (_, urlResponse) = try await URLSession(configuration: .ephemeral).data(for: request)

            guard let response = urlResponse as? HTTPURLResponse, response.statusCode == 200 || response.statusCode == 201 else {
                throw FixtureRecordingError.conversationSeedingFailed
            }
        }

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

            for note in Self.notes {
                let path = "\(notesFolder)/\(note.name)"
                try write(note.contents, to: path)
                try FileManager.default.setAttributes([.modificationDate: note.modification], ofItemAtPath: baselineDirectory.appendingPathComponent(path).path)
            }

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
