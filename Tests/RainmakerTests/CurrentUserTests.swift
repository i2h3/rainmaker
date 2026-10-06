// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About ``Server/currentUser()`` against recorded responses of a live server.
///
/// The statuses and bodies a live server cannot be made to answer with are covered by ``CurrentUserRequestTests`` instead.
///
@Suite("Current User") struct CurrentUserTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.currentUser()
        }
    }

    @Test("Fetch", arguments: ServerVersion.allCases)
    func fetch(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let user = try await server.currentUser()

        // The recording containers provision the account "admin", which logs in with its identifier.
        #expect(user.id == "admin")
        #expect(user.displayName.isEmpty == false)
    }
}
