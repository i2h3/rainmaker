// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// Deleting items on the server.
///
@Suite("Deletes") struct DeleteTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.delete("/Readme.md")
        }
    }

    @Test("File", arguments: ServerVersion.allCases)
    func file(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            try await server.delete("/Readme.md")
        }
    }

    @Test("Directory", arguments: ServerVersion.allCases)
    func directory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            try await server.delete("/Documents")
        }
    }

    @Test("Inexistent", arguments: ServerVersion.allCases)
    func inexistent(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: RainmakerError.notFound) {
            try await server.delete("/This does not exist")
        }
    }
}
