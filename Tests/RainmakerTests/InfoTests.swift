// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// Retrieving metadata of specific items from the server.
///
@Suite("Infos") struct InfoTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.info("/")
        }
    }

    @Test("File", arguments: ServerVersion.allCases)
    func file(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            _ = try await server.info("/Readme.md")
        }
    }

    @Test("Directory", arguments: ServerVersion.allCases)
    func directory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            _ = try await server.info("/")
        }
    }

    @Test("Inexistent", arguments: ServerVersion.allCases)
    func inexistent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.info("/This does not exist")
        }
    }
}
