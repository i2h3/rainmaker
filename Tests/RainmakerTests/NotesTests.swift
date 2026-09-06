// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About listing the notes of the authenticated user.
///
/// The fixtures backing this suite are recorded against a container which has the notes app installed on demand, because that app is not part of a Nextcloud installation. See ``FixtureOrchestrator/enabledApps``. The notes themselves are seeded as files in the account's notes folder by ``FixtureProvisioner``, which also stamps them with fixed modification dates so that what the server reports as `modified` is reproducible.
///
/// How a request is built, how an unavailable app surfaces and how the two response shapes decode is covered by ``NotesRequestTests`` instead, which drives a mock rather than the fixture tree.
///
@Suite("Notes") struct NotesTests: ServerTesting {
    ///
    /// A moment before any recording can have taken place, so the server finds every note changed since then.
    ///
    let beforeRecording = Date(timeIntervalSince1970: 1_700_000_000)

    ///
    /// A moment after any recording can have taken place, so the server finds no note changed since then and reduces all of them to their identifiers.
    ///
    let afterRecording = Date(timeIntervalSince1970: 4_102_444_800)

    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.notes()
        }
    }

    @Test("Fetch", arguments: ServerVersion.allCases)
    func fetch(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let notes = try await server.notes()

        // Downstream projects rely on the count to learn whether and how many notes exist.
        #expect(notes.isEmpty == false)
        #expect(notes.count == 2)

        // The notes are looked up by title rather than by position or identifier: the server orders them by how it walks the notes folder, and the identifiers it assigns depend on the deployment.
        let uncategorized = try #require(notes.first { $0.title == "Rainmaker" })
        #expect(uncategorized.content == "# Rainmaker\n")

        // An empty category is what the server sends for a note which is not filed under one.
        #expect(uncategorized.category == "")
        #expect(uncategorized.isFavorite == false)
        #expect(uncategorized.isReadOnly == false)

        // Pins the conversion of the server's whole seconds since the Unix epoch, which the provisioner stamped onto the seeded file.
        #expect(uncategorized.modification == Date(timeIntervalSince1970: 1_700_000_000))

        // Only the presence of the entity tag is asserted. It is a content hash differing per deployment, so it is canonicalized when recorded, and during a recording run the test is handed the live value rather than the canonical one. Pinning the placeholder would therefore fail every recording. That the canonicalization happens at all is covered by ``FixtureCanonicalizerTests``.
        #expect(uncategorized.entityTag.isEmpty == false)
        #expect(uncategorized.description == "Rainmaker")

        // A note in a sub-folder of the notes folder is reported under that folder as its category.
        let categorized = try #require(notes.first { $0.title == "Pancakes" })
        #expect(categorized.category == "Recipes")
        #expect(categorized.content == "# Pancakes\n")
        #expect(categorized.modification == Date(timeIntervalSince1970: 1_600_000_000))

        // The identifiers are assigned by the server and are only meaningful in being present and telling the notes apart.
        #expect(notes.allSatisfy { $0.id > 0 })
        #expect(Set(notes.map(\.id)).count == notes.count)
    }

    @Test("Fetch None", arguments: ServerVersion.allCases)
    func fetchNone(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let notes = try await server.notes()

        // An account whose notes folder was removed beforehand has no notes at all, which the server reports as an empty list rather than as an error.
        #expect(notes.isEmpty)
    }

    @Test("Settings", arguments: ServerVersion.allCases)
    func settings(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let settings = try await server.notesSettings()

        // Neither value is pinned to a literal: the folder is derived from the account's locale, so the container's language decides it, and the suffix is a user setting. What matters is that the server reports something usable, since the recording provisions its notes into exactly this folder.
        #expect(settings.notesPath.isEmpty == false)
        #expect(settings.fileSuffix.hasPrefix("."))
    }

    @Test("Fetch Everything Changed", arguments: ServerVersion.allCases)
    func fetchEverythingChanged(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let changes = try await server.notes(changedSince: beforeRecording)

        // The server's record of when it last saw each note is younger than the requested moment, so it prunes nothing and answers with every note in full.
        #expect(changes.changed.count == 2)
        #expect(changes.unchanged.isEmpty)
        #expect(changes.changed.map(\.title).sorted() == ["Pancakes", "Rainmaker"])
    }

    @Test("Fetch Nothing Changed", arguments: ServerVersion.allCases)
    func fetchNothingChanged(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let changes = try await server.notes(changedSince: afterRecording)

        // The requested moment is younger than the server's record of every note, so all of them are reduced to their identifiers. This is the shape a client polling frequently sees most of the time.
        #expect(changes.changed.isEmpty)
        #expect(changes.unchanged.count == 2)
        #expect(changes.unchanged.allSatisfy { $0 > 0 })
        #expect(Set(changes.unchanged).count == changes.unchanged.count)
    }
}
