// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About folder content listing.
///
@Suite("Listing Tests") struct ListingTests {
    private static let serverAddress = FileManager.default.temporaryDirectory
    private static let password = "admin"
    private static let user = "admin"

    @Test("List Root Folder Content", arguments: ServerVersion.allCases)
    func listRootFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try Server(address: Self.serverAddress, password: Self.password, user: Self.user, session: URLTestSession(serverVersion: serverVersion))
        let items = try await server.content(at: "/")

        #expect(items.count == 10, "Expected 10 default children!")
        #expect(items.count(where: { $0.isDirectory }) == 4, "Expected 4 subfolders!")
    }

    @Test("List Documents Folder Content", arguments: ServerVersion.allCases)
    func listDocumentsFolderContent(_ serverVersion: ServerVersion) async throws {
        let server = try Server(address: Self.serverAddress, password: Self.password, user: Self.user, session: URLTestSession(serverVersion: serverVersion))
        let items = try await server.content(at: "/Documents")

        #expect(items.count == 5, "Expected the 5 default children!")
        #expect(items.count(where: { $0.isDirectory }) == 1, "Expected 1 subfolder!")
    }
}
