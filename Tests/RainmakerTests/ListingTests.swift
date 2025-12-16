// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About folder content listing.
///
@Suite("Listing Tests") struct ListingTests {
    private static let serverAddress = URL(string: "http://localhost/")!
    private static let password = "admin"
    private static let user = "admin"

    @Test("List Root Folder Content", arguments: ServerVersion.allCases)
    func listRootFolderContent(_ serverVersion: ServerVersion) async throws {
        let session = try URLTestSession(serverVersion: serverVersion)
        let server = Server(address: Self.serverAddress, password: Self.password, user: Self.user, session: session)
        let stream = try await server.enumerate(at: "/", recursively: false)
        var items = [Item]()

        for try await item in stream {
            items.append(item)
        }

        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Readme.md" })
    }

    @Test("List Documents Folder Content", arguments: ServerVersion.allCases)
    func listDocumentsFolderContent(_ serverVersion: ServerVersion) async throws {
        let session = try URLTestSession(serverVersion: serverVersion)
        let server = Server(address: Self.serverAddress, password: Self.password, user: Self.user, session: session)
        let stream = try await server.enumerate(at: "/Documents", recursively: false)
        var items = [Item]()

        for try await item in stream {
            items.append(item)
        }

        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Documents/Example.md" })
    }

    @Test("List All Content Recursively and Asynchronously", arguments: ServerVersion.allCases)
    func listAllContentRecursivelyAndAsynchronously(_ serverVersion: ServerVersion) async throws {
        let session = try URLTestSession(serverVersion: serverVersion)
        let server = Server(address: Self.serverAddress, password: Self.password, user: Self.user, session: session)
        var items = [Item]()
        let stream: AsyncThrowingStream<Item, Error> = try await server.enumerate(at: "/", recursively: true)

        for try await item in stream {
            items.append(item)
        }

        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Readme.md" })
        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Documents/Example.md" })
        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Photos/Frog.jpg" })
        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Templates/Brainstorming.whiteboard" })
    }
}
