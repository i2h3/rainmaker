// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About creating remote directories via WebDAV MKCOL.
///
@Suite("Create Directory") struct CreateDirectoryTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.createDirectory("/Rainmaker")
        }
    }

    @Test("Create New Directory", arguments: ServerVersion.allCases)
    func createNewDirectory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        try await server.createDirectory("/Rainmaker")
    }

    @Test("Already Exists", arguments: ServerVersion.allCases)
    func alreadyExists(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect {
            try await server.createDirectory("/Documents")
        } throws: { error in
            guard case RainmakerError.fileAlreadyExists = error else {
                return false
            }

            return true
        }
    }

    @Test("Parent Missing", arguments: ServerVersion.allCases)
    func parentMissing(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: RainmakerError.notFound) {
            try await server.createDirectory("/Inexistent/Child")
        }
    }
}
