// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// Login flow related tests.
///
@Suite("Login") struct LoginTests: ServerTesting {
    @Test("Fetch Login Information", arguments: ServerVersion.allCases)
    func fetchLoginInformation(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            _ = try await server.login()
        }
    }
}
