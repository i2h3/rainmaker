// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About listing, restoring and emptying the server trash bin.
///
@Suite("Trash") struct TrashTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.trash()
        }
    }

    @Test("List Trash", arguments: ServerVersion.allCases)
    func listTrash(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items = try await server.trash()

        // The trash bin root itself is filtered out, leaving only the two trashed items.
        #expect(items.count == 2)

        let note = try #require(items.first { $0.name == "Note.txt" })
        #expect(note.id == "Note.txt.d1700000000")
        #expect(note.path == "/Note.txt.d1700000000")
        #expect(note.href.path() == "/remote.php/dav/trashbin/admin/trash/Note.txt.d1700000000")
        #expect(note.originalLocation == "Note.txt")
        #expect(note.isDirectory == false)
        #expect(note.size == 29)
        #expect(note.deletion == Date(timeIntervalSince1970: 1_700_000_000))

        let photos = try #require(items.first { $0.name == "Photos" })
        #expect(photos.id == "Photos.d1699990000")
        #expect(photos.originalLocation == "Photos")
        #expect(photos.isDirectory == true)
    }

    @Test("Restore Item", arguments: ServerVersion.allCases)
    func restoreItem(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            try await server.restore("Note.txt.d1700000000")
        }
    }

    @Test("Empty Trash", arguments: ServerVersion.allCases)
    func emptyTrash(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            try await server.emptyTrash()
        }
    }
}
