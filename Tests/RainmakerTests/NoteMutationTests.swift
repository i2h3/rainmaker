// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About creating, changing and deleting notes of the authenticated user against the notes app.
///
/// The fixtures backing this suite are recorded like those of ``NotesTests``, against a container with the notes app installed. Every test deletes the notes it creates and never changes the notes ``FixtureProvisioner`` seeds, because the baseline reset between recordings removes what a test leaves behind but does not restore a seeded note which is newer on the server than in the baseline.
///
/// The requests of one test differ in method or path, which is what lets the fixture tree replay them: the identifier the server assigned is part of the path of every request after the creation, and it is taken from the recorded creation rather than pinned. Moments are pinned so that the `modified` the server reports replays as well. How the requests are built and how the statuses the notes app may answer with map onto ``RainmakerError`` is covered by ``NoteWritingRequestTests`` instead.
///
/// Calls go through ``Serving``, whose requirements have no default arguments, so every argument is spelled out.
///
@Suite("Note Mutations") struct NoteMutationTests: ServerTesting {
    ///
    /// The moment the notes of this suite are created with, pinned so that the recorded `modified` replays.
    ///
    let creation = Date(timeIntervalSince1970: 1_650_000_000)

    ///
    /// The moment the notes of this suite are changed with, a little after ``creation``.
    ///
    let change = Date(timeIntervalSince1970: 1_650_000_100)

    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so every call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.createNote(title: "Rainmaker Test", category: "", content: "", modification: nil, isFavorite: false)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.updateNote(1, title: nil, category: nil, content: "", modification: nil, isFavorite: nil, ifMatching: nil)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.deleteNote(1)
        }
    }

    @Test("Lifecycle", arguments: ServerVersion.allCases)
    func lifecycle(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let created = try await server.createNote(title: "Rainmaker Test", category: "Rainmaker Tests", content: "# Test\n", modification: creation, isFavorite: false)

        // The server stores what it was given, and the moment is stamped onto the file after the content was written, so it is kept.
        #expect(created.title == "Rainmaker Test")
        #expect(created.category == "Rainmaker Tests")
        #expect(created.content == "# Test\n")
        #expect(created.modification == creation)
        #expect(created.isFavorite == false)
        #expect(created.isReadOnly == false)
        #expect(created.hasError == false)
        #expect(created.entityTag.isEmpty == false)

        // The category becomes a folder inside the notes folder, whose name depends on the container's locale.
        #expect(created.path?.hasSuffix("/Rainmaker Tests/Rainmaker Test.md") == true)

        // The tag of the note just created is current, so the change based on it applies.
        let changed = try await server.updateNote(created.id, title: nil, category: nil, content: "# Changed\n", modification: change, isFavorite: nil, ifMatching: created.entityTag)

        #expect(changed.id == created.id)
        #expect(changed.content == "# Changed\n")
        #expect(changed.modification == change)
        #expect(changed.title == created.title)
        #expect(changed.category == created.category)

        try await server.deleteNote(created.id)

        // The deleted note is gone, which a lookup reports as not found rather than as an unavailable app.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.note(created.id)
        }
    }

    @Test("Conflict", arguments: ServerVersion.allCases)
    func conflict(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let created = try await server.createNote(title: "Rainmaker Test", category: "", content: "# Test\n", modification: creation, isFavorite: false)

        // A tag the note never had does not match, so the server changes nothing and sends the note as it is now.
        await #expect {
            _ = try await server.updateNote(created.id, title: nil, category: nil, content: "# Changed\n", modification: change, isFavorite: nil, ifMatching: "stale")
        } throws: { error in
            guard case let RainmakerError.noteConflict(current: current) = error else {
                return false
            }

            return current.id == created.id && current.content == "# Test\n" && current.modification == creation && current.entityTag.isEmpty == false
        }

        try await server.deleteNote(created.id)
    }

    @Test("Favorite", arguments: ServerVersion.allCases)
    func favorite(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let created = try await server.createNote(title: "Rainmaker Test", category: "", content: "# Test\n", modification: creation, isFavorite: false)
        let changed = try await server.updateNote(created.id, title: nil, category: nil, content: nil, modification: nil, isFavorite: true, ifMatching: nil)

        // Only the favorite changed, which the server keeps apart from the note's file, so the content and the moment stay as they were.
        #expect(changed.id == created.id)
        #expect(changed.isFavorite)
        #expect(changed.content == "# Test\n")
        #expect(changed.modification == creation)

        try await server.deleteNote(created.id)
    }

    @Test("Rename", arguments: ServerVersion.allCases)
    func rename(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let created = try await server.createNote(title: "Rainmaker Test", category: "", content: "# Test\n", modification: creation, isFavorite: false)
        let renamed = try await server.updateNote(created.id, title: "Rainmaker Renamed", category: "Rainmaker Tests", content: nil, modification: nil, isFavorite: nil, ifMatching: nil)

        // Renaming and moving a note moves its file, but the note keeps its identifier and content.
        #expect(renamed.id == created.id)
        #expect(renamed.title == "Rainmaker Renamed")
        #expect(renamed.category == "Rainmaker Tests")
        #expect(renamed.content == "# Test\n")
        #expect(renamed.path?.hasSuffix("/Rainmaker Tests/Rainmaker Renamed.md") == true)

        try await server.deleteNote(created.id)
    }

    @Test("Sanitized Title", arguments: ServerVersion.allCases)
    func sanitizedTitle(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let created = try await server.createNote(title: "A/B:C", category: "", content: "# Test\n", modification: creation, isFavorite: false)

        // The title becomes a file name, so the server removes what cannot be part of one, and the caller adopts the title it returns.
        #expect(created.title != "A/B:C")
        #expect(created.title == "ABC")
        #expect(created.path?.hasSuffix("/ABC.md") == true)

        try await server.deleteNote(created.id)
    }

    @Test("Delete Missing", arguments: ServerVersion.allCases)
    func deleteMissing(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // No deployment assigns an identifier this large to a baseline with two notes, so the notes app itself answers that the note does not exist, which a caller takes as the note being gone already.
        await #expect(throws: RainmakerError.notFound) {
            try await server.deleteNote(999_999_999)
        }
    }
}
