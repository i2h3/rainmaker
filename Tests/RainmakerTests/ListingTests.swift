// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About folder content listing.
///
@Suite("Listings") struct ListingTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            let _: [Item] = try await server.enumerate(at: "/", recursively: false)
        }
    }

    @Test("Root Folder", arguments: ServerVersion.allCases)
    func listRootFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/", recursively: false)
        let readme = try #require(items.first { $0.name == "Readme.md" })
        #expect(readme.path == "/Readme.md")
        #expect(readme.href.path() == "/remote.php/dav/files/admin/Readme.md")
    }

    @Test("Documents Folder", arguments: ServerVersion.allCases)
    func listDocumentsFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Documents", recursively: false)
        let example = try #require(items.first { $0.name == "Example.md" })
        #expect(example.path == "/Documents/Example.md")
        #expect(example.href.path() == "/remote.php/dav/files/admin/Documents/Example.md")
    }

    @Test("All Content Recursively and Asynchronously", arguments: ServerVersion.allCases)
    func listAllContentRecursivelyAndAsynchronously(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/", recursively: true)
        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Readme.md" })
        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Documents/Example.md" })
        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Photos/Frog.jpg" })
        #expect(items.contains { $0.href.path() == "/remote.php/dav/files/admin/Templates/Brainstorming.whiteboard" })
    }

    @Test("Whitespace Folder", arguments: ServerVersion.allCases)
    func listWhitespaceFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Special Characters", recursively: false)
        #expect(items.contains { $0.name == ":" })
        #expect(items.contains { $0.name == "?" })
        #expect(items.contains { $0.name == "&" })
        #expect(items.contains { $0.name == "#" })
        #expect(items.contains { $0.name == "%" })
    }

    @Test("Percent-encoded Folder", arguments: ServerVersion.allCases)
    func listPercentEncodedFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Special%20Characters", recursively: false)
        #expect(items.contains { $0.name == ":" })
        #expect(items.contains { $0.name == "?" })
        #expect(items.contains { $0.name == "&" })
        #expect(items.contains { $0.name == "#" })
        #expect(items.contains { $0.name == "%" })
    }

    @Test(": Folder", arguments: ServerVersion.allCases)
    func listColonFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Special Characters/:", recursively: false)
        let readme = try #require(items.first { $0.name == "Readme.md" })
        #expect(readme.href.path() == "/remote.php/dav/files/admin/Special%20Characters/:/Readme.md")
        #expect(readme.path == "/Special Characters/:/Readme.md")
    }

    @Test("? Folder", arguments: ServerVersion.allCases)
    func listQuestionMarkFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Special Characters/?", recursively: false)
        let readme = try #require(items.first { $0.name == "Readme.md" })
        #expect(readme.href.path() == "/remote.php/dav/files/admin/Special%20Characters/%3f/Readme.md")
        #expect(readme.path == "/Special Characters/?/Readme.md")
    }

    @Test("& Folder", arguments: ServerVersion.allCases)
    func listAmpersandFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Special Characters/&", recursively: false)
        let readme = try #require(items.first { $0.name == "Readme.md" })
        #expect(readme.href.path() == "/remote.php/dav/files/admin/Special%20Characters/%26/Readme.md")
        #expect(readme.path == "/Special Characters/&/Readme.md")
    }

    @Test("# Folder", arguments: ServerVersion.allCases)
    func listHashFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Special Characters/#", recursively: false)
        let readme = try #require(items.first { $0.name == "Readme.md" })
        #expect(readme.href.path() == "/remote.php/dav/files/admin/Special%20Characters/%23/Readme.md")
        #expect(readme.path == "/Special Characters/#/Readme.md")
    }

    @Test("% Folder", arguments: ServerVersion.allCases)
    func listPercentFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items: [Item] = try await server.enumerate(at: "/Special Characters/%", recursively: false)
        let readme = try #require(items.first { $0.name == "Readme.md" })
        #expect(readme.href.path() == "/remote.php/dav/files/admin/Special%20Characters/%25/Readme.md")
        #expect(readme.path == "/Special Characters/%/Readme.md")
    }
}
