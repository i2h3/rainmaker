// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About relocating (moving/renaming) remote items on the server.
///
@Suite("Moves") struct MoveTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.move("/Readme.md", to: "/Renamed.md", overwrite: false)
        }
    }

    @Test("Move File", arguments: ServerVersion.allCases)
    func moveFile(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            try await server.move("/Readme.md", to: "/Documents/Readme.md", overwrite: false)
        }
    }

    @Test("Move Directory", arguments: ServerVersion.allCases)
    func moveDirectory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            try await server.move("/Documents", to: "/Archive", overwrite: false)
        }
    }

    @Test("Inexistent Source", arguments: ServerVersion.allCases)
    func inexistentSource(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: RainmakerError.notFound) {
            try await server.move("/This does not exist", to: "/Wherever", overwrite: false)
        }
    }

    @Test("Parent Missing", arguments: ServerVersion.allCases)
    func parentMissing(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: RainmakerError.notFound) {
            try await server.move("/Readme.md", to: "/Inexistent/Child.md", overwrite: false)
        }
    }

    @Test("Overwrite Existing", arguments: ServerVersion.allCases)
    func overwriteExisting(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            try await server.move("/Readme.md", to: "/Existing.md", overwrite: true)
        }
    }

    @Test("Conflict When Exists", arguments: ServerVersion.allCases)
    func conflictWhenExists(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect {
            try await server.move("/Readme.md", to: "/Existing.md", overwrite: false)
        } throws: { error in
            guard case RainmakerError.destinationExists = error else {
                return false
            }

            return true
        }
    }
}
