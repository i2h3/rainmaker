// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About listing the notes of the authenticated user and retrieving a single one of them.
///
/// The fixtures backing this suite are recorded against a container which has the notes app installed on demand, because that app is not part of a Nextcloud installation. See ``FixtureOrchestrator/enabledApps``. The notes themselves are seeded as files in the account's notes folder by ``FixtureProvisioner``, which also stamps them with fixed modification dates so that what the server reports as `modified` is reproducible.
///
/// How a request is built, how an unavailable app surfaces and how the two response shapes decode is covered by ``NotesRequestTests`` instead, which drives a mock rather than the fixture tree, and ``SingleNoteRequestTests`` does the same for the retrieval of a single note.
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

        // A note the server read without trouble reports no failure, which is what makes the flag meaningful on the ones that do.
        #expect(uncategorized.hasError == false)
        #expect(uncategorized.errorType.isEmpty)

        // Pins the conversion of the server's whole seconds since the Unix epoch, which the provisioner stamped onto the seeded file.
        #expect(uncategorized.modification == Date(timeIntervalSince1970: 1_700_000_000))

        // Only the presence of the entity tag is asserted. It is a content hash differing per deployment, so it is canonicalized when recorded, and during a recording run the test is handed the live value rather than the canonical one. Pinning the placeholder would therefore fail every recording. That the canonicalization happens at all is covered by ``FixtureCanonicalizerTests``.
        #expect(uncategorized.entityTag.isEmpty == false)
        #expect(uncategorized.description == "Rainmaker")

        // The path is pinned only below the notes folder, whose name is derived from the container's locale. The seeded notes are not shared with anyone.
        #expect(uncategorized.path?.hasPrefix("/") == true)
        #expect(uncategorized.path?.hasSuffix("/Rainmaker.md") == true)
        #expect(uncategorized.isShared == false)
        #expect(uncategorized.shareTypes.isEmpty)

        // A note in a sub-folder of the notes folder is reported under that folder as its category.
        let categorized = try #require(notes.first { $0.title == "Pancakes" })
        #expect(categorized.category == "Recipes")
        #expect(categorized.content == "# Pancakes\n")
        #expect(categorized.modification == Date(timeIntervalSince1970: 1_600_000_000))

        // The category is the folder the note's file sits in, which the path reflects.
        #expect(categorized.path?.hasSuffix("/Recipes/Pancakes.md") == true)

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

        // The capabilities say which release of the notes app answers, which decides whether the preferences of newer releases are sent. Branching on them rather than on the server version keeps the test independent of which release the app store hands each server version.
        let notes = try #require(try await server.capabilities().get(Notes.self))
        let settings = try await server.notesSettings()

        // Neither value is pinned to a literal: the folder is derived from the account's locale, so the container's language decides it, and the suffix is a user setting. What matters is that the server reports something usable, since the recording provisions its notes into exactly this folder.
        #expect(settings.notesPath.isEmpty == false)
        #expect(settings.fileSuffix.hasPrefix("."))

        // Every supported release sends a mode, and it is one of the known ones rather than something which decoded as absent.
        #expect(settings.noteMode != nil)

        if notes.isAppVersion(atLeast: "6.1.0") {
            #expect(settings.showsHiddenFiles != nil)
            #expect(settings.loadsRecentNoteOnStartUp != nil)
        } else {
            #expect(settings.showsHiddenFiles == nil)
            #expect(settings.loadsRecentNoteOnStartUp == nil)
        }
    }

    @Test("Fetch Everything Changed", arguments: ServerVersion.allCases)
    func fetchEverythingChanged(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let changes = try await server.notes(changedSince: beforeRecording)

        // The server's record of when it last saw each note is younger than the requested moment, so it prunes nothing and answers with every note in full.
        #expect(changes.changed.count == 2)
        #expect(changes.unchanged.isEmpty)
        #expect(changes.changed.map(\.title).sorted() == ["Pancakes", "Rainmaker"])

        // Only the presence of the moment and the entity tag is asserted, for the same reason as with the entity tag of a note: both are canonicalized when recorded, while a recording run is handed the live values.
        #expect(changes.lastModified != nil)
        #expect(changes.entityTag?.isEmpty == false)

        // No chunk size was asked for, so the server answers in one response which lists every note.
        #expect(changes.isComplete)
        #expect(changes.pendingCount == nil)
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

        // A response without a single note in full still says what to continue from and how to ask whether it changed.
        #expect(changes.lastModified != nil)
        #expect(changes.entityTag?.isEmpty == false)
        #expect(changes.isComplete)
    }

    @Test("Fetch First Chunk", arguments: ServerVersion.allCases)
    func fetchFirstChunk(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let changes = try await server.notes(changedSince: beforeRecording, chunkSize: 1, continuingAfter: nil)

        // Both seeded notes changed since the requested moment, so a chunk of one sends one of them in full and leaves the other pending. Which one comes first depends on when the server noticed each, so only the count is asserted.
        #expect(changes.changed.count == 1)
        #expect(changes.pendingCount == 1)

        // A chunk which is not the last one lists no identifiers, which is why deletions must not be derived from it.
        #expect(changes.unchanged.isEmpty)
        #expect(changes.isComplete == false)

        // Only the presence of the cursor and the moment is asserted, because both are canonicalized when recorded, while a recording run is handed the live values.
        #expect(changes.chunkCursor?.isEmpty == false)
        #expect(changes.lastModified != nil)
    }

    @Test("Fetch Summaries", arguments: ServerVersion.allCases)
    func fetchSummaries(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let changes = try await server.noteSummaries(changedSince: beforeRecording)

        // The server prunes nothing, as for ``fetchEverythingChanged(_:)``, and describes every note in full but for its text, which the recorded body does not carry at all.
        #expect(changes.changed.count == 2)
        #expect(changes.unchanged.isEmpty)
        #expect(changes.changed.map(\.title).sorted() == ["Pancakes", "Rainmaker"])

        let uncategorized = try #require(changes.changed.first { $0.title == "Rainmaker" })
        #expect(uncategorized.category == "")
        #expect(uncategorized.isFavorite == false)
        #expect(uncategorized.isReadOnly == false)
        #expect(uncategorized.modification == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(uncategorized.entityTag.isEmpty == false)
        #expect(uncategorized.path?.hasSuffix("/Rainmaker.md") == true)
        #expect(uncategorized.isShared == false)
        #expect(uncategorized.shareTypes.isEmpty)

        let categorized = try #require(changes.changed.first { $0.title == "Pancakes" })
        #expect(categorized.category == "Recipes")
        #expect(categorized.modification == Date(timeIntervalSince1970: 1_600_000_000))
        #expect(categorized.path?.hasSuffix("/Recipes/Pancakes.md") == true)

        // The headers are read as for a listing with text, so only their presence is asserted for the reasons ``fetchEverythingChanged(_:)`` gives.
        #expect(changes.lastModified != nil)
        #expect(changes.entityTag?.isEmpty == false)
        #expect(changes.isComplete)
        #expect(changes.pendingCount == nil)
    }

    @Test("Fetch Summaries First Chunk", arguments: ServerVersion.allCases)
    func fetchSummariesFirstChunk(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let changes = try await server.noteSummaries(changedSince: beforeRecording, chunkSize: 1, continuingAfter: nil)

        // Chunking works on summaries as on notes with their text, see ``fetchFirstChunk(_:)``.
        #expect(changes.changed.count == 1)
        #expect(changes.pendingCount == 1)
        #expect(changes.unchanged.isEmpty)
        #expect(changes.isComplete == false)
        #expect(changes.chunkCursor?.isEmpty == false)
        #expect(changes.lastModified != nil)
    }

    @Test("Fetch Note", arguments: ServerVersion.allCases)
    func fetchNote(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // The identifier is assigned by the server, so it is taken from the listing rather than pinned. The recorded lookup is filed under that identifier, which is why both requests are recorded together.
        let listed = try #require(try await server.notes().first { $0.title == "Rainmaker" })
        let note = try await server.note(listed.id)

        // The lookup reports the very note the listing does, field by field, which is what lets a client refresh one note without listing all of them.
        #expect(note == listed)
        #expect(note.content == "# Rainmaker\n")
        #expect(note.category == "")
        #expect(note.modification == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(note.path?.hasSuffix("/Rainmaker.md") == true)
        #expect(note.hasError == false)
        #expect(note.entityTag.isEmpty == false)
    }

    @Test("Fetch Unchanged Note", arguments: ServerVersion.allCases)
    func fetchUnchangedNote(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let listed = try #require(try await server.notes().first { $0.title == "Rainmaker" })

        // The entity tag the listing reports for a note is the one the server compares a conditional lookup against, so nothing changed in between and the server answers with not modified. When recorded, the live tag is sent and the server's real answer is captured, while a replay finds that answer by method and path alone.
        let note = try await server.note(listed.id, ifChangedFrom: listed.entityTag)
        #expect(note == nil)
    }

    @Test("Fetch Missing Note", arguments: ServerVersion.allCases)
    func fetchMissingNote(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // No deployment assigns an identifier this large to a baseline with two notes, so the notes app itself answers that the note does not exist, which is told apart from an absent app by the header it adds.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.note(999_999_999)
        }
    }
}
