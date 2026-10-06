// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About adding, retrieving and deleting the attachments of notes of the authenticated user against the notes app.
///
/// The fixtures backing this suite are recorded like those of ``NoteMutationTests``, against a container with the notes app installed. Every test creates the note it attaches a file to and deletes everything it created again, never touching the notes ``FixtureProvisioner`` seeds.
///
/// Where an uploaded attachment lands and whether it can be deleted depends on the release of the notes app rather than on the server, so each test records the capabilities first and branches on ``Notes/storesAttachmentsPerNote`` and ``Notes/supportsAttachmentDeletion``. Releases which do not keep attachments per note store them under a random name next to the note and offer no deletion, so the tests remove such an attachment over WebDAV through the path of the note instead.
///
/// The identifier of the note is part of the path of every request after its creation, and the path of the attachment is only sent as a query parameter, which ``FixtureLocator`` ignores, so every request of a test differs in method or path and replays from the fixture tree. How the requests are built is covered by ``NoteAttachmentRequestTests`` instead.
///
/// Calls go through ``Serving``, whose requirements have no default arguments, so every argument is spelled out.
///
@Suite("Note Attachments") struct NoteAttachmentTests: ServerTesting {
    ///
    /// The moment the notes of this suite are created with, pinned so that the recorded `modified` replays.
    ///
    let creation = Date(timeIntervalSince1970: 1_650_000_000)

    ///
    /// The bytes of a PNG image of a single transparent pixel, which is what the suite attaches.
    ///
    let image = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00, 0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])

    ///
    /// Check the path the server stored an attachment named `Rainmaker.png` at, which depends on the release of the notes app.
    ///
    /// - Parameters:
    ///     - path: The path ``Serving/addAttachment(_:toNote:fileName:)`` returned.
    ///     - note: The note the attachment was added to.
    ///     - notes: The capability of the notes app which answered.
    ///
    private func expectStoredPath(_ path: String, of note: Note, by notes: Notes) {
        if notes.storesAttachmentsPerNote {
            // The file keeps its name in the folder of the note's own attachments.
            #expect(path == ".attachments.\(note.id)/Rainmaker.png")
        } else {
            // The file lands next to the note under a random name which keeps only the extension.
            #expect(path.hasSuffix(".png"))
            #expect(path.count == 36)
            #expect(path.contains("/") == false)
        }
    }

    ///
    /// Remove an attachment and the note it belongs to, in the way the release of the notes app allows.
    ///
    /// Releases which keep attachments per note delete them along with the note. Older releases leave them behind, so the attachment is deleted over WebDAV first, from the folder the note's file is in, which also lets the server remove the folder of the note's category once the note is deleted.
    ///
    /// - Parameters:
    ///     - path: The path of the attachment relative to the folder of the note's category.
    ///     - note: The note the attachment belongs to.
    ///     - notes: The capability of the notes app which answered.
    ///     - server: The server to remove them from.
    ///
    private func remove(attachmentAt path: String, of note: Note, by notes: Notes, from server: any Serving) async throws {
        if notes.storesAttachmentsPerNote == false {
            let notePath = try #require(note.path)
            let folder = (notePath as NSString).deletingLastPathComponent
            try await server.delete("\(folder)/\(path)")
        }

        try await server.deleteNote(note.id)
    }

    @Test("Lifecycle", arguments: ServerVersion.allCases)
    func lifecycle(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let notes = try #require(try await server.capabilities().get(Notes.self))
        let note = try await server.createNote(title: "Rainmaker Attachment Test", category: "Rainmaker Tests", content: "# Test\n", modification: creation, isFavorite: false)
        let path = try await server.addAttachment(image, toNote: note.id, fileName: "Rainmaker.png")

        expectStoredPath(path, of: note, by: notes)

        // The path is relative to the folder of the note's category, which is what the retrieval resolves it against, and the type is derived from the extension.
        let attachment = try await server.attachment(at: path, ofNote: note.id)

        #expect(attachment.data == image)
        #expect(attachment.contentType == "image/png")

        if notes.supportsAttachmentDeletion {
            // Deleting the attachment also removes its folder once it is empty, which the deletion of the note would otherwise take care of.
            try await server.deleteAttachment(at: path, ofNote: note.id)
            try await server.deleteNote(note.id)
        } else {
            // Older releases route no deletion of attachments, which the server refuses before the app is involved.
            await #expect(throws: RainmakerError.methodNotAllowed) {
                try await server.deleteAttachment(at: path, ofNote: note.id)
            }

            try await remove(attachmentAt: path, of: note, by: notes, from: server)
        }
    }

    @Test("Download", arguments: ServerVersion.allCases)
    func download(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let notes = try #require(try await server.capabilities().get(Notes.self))
        let note = try await server.createNote(title: "Rainmaker Attachment Test", category: "Rainmaker Tests", content: "# Test\n", modification: creation, isFavorite: false)
        let path = try await server.addAttachment(image, toNote: note.id, fileName: "Rainmaker.png")

        expectStoredPath(path, of: note, by: notes)

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("NoteAttachmentTests-\(UUID().uuidString).png")

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        // The file is streamed to disk rather than handed over in memory, and arrives with the same bytes and type.
        let file = try await server.downloadAttachment(at: path, ofNote: note.id, to: destination, force: false)

        #expect(file.location == destination)
        #expect(file.contentType == "image/png")
        #expect(try Data(contentsOf: destination) == image)

        try await remove(attachmentAt: path, of: note, by: notes, from: server)
    }

    @Test("Missing Attachment", arguments: ServerVersion.allCases)
    func missingAttachment(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let note = try await server.createNote(title: "Rainmaker Attachment Test", category: "", content: "# Test\n", modification: creation, isFavorite: false)

        // Every release answers a path which names nothing with a bare not found status.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.attachment(at: "Missing.png", ofNote: note.id)
        }

        try await server.deleteNote(note.id)
    }
}
