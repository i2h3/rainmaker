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

        // The "files" app is always advertised, so it makes for a stable assertion.
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

        // The Talk app, which `FixtureOrchestrator` installs for `ConversationsTests`, registers itself ahead of everything else with a negative order and is therefore what the server reports as the default app. That is why the flag is asserted on the entry which actually carries it rather than on "files", which held it before Talk was part of the baseline.
        #expect(files.isDefault == false)

        let talk = try #require(items.first { $0.id == "spreed" })
        #expect(talk.app == "spreed")
        #expect(talk.order == -5)
        #expect(talk.isDefault)
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
