// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// Apps navigation related tests.
///
@Suite("Navigation") struct NavigationTests: ServerTesting {
    @Test("Authenticated Fetch", arguments: ServerVersion.allCases)
    func fetchAuthenticated(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items = try await server.navigation()

        #expect(items.isEmpty == false)

        // The "files" app is always advertised and is the default app, so it makes for a stable assertion.
        let files = try #require(items.first { $0.id == "files" })
        #expect(files.name == "Dateien")
        #expect(files.app == "files")
        #expect(files.href == "/apps/files/")
        #expect(files.icon == "/apps/files/img/app.svg")
        #expect(files.type == "link")
        #expect(files.order == 0)
        #expect(files.unread == 0)
        #expect(files.classes == "")
        #expect(files.isActive == false)
        #expect(files.isDefault)
    }

    @Test("Unauthenticated Fetch", arguments: ServerVersion.allCases)
    func fetchUnauthenticated(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.navigation()
        }
    }
}
