// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// Login flow related tests.
///
/// The statuses and bodies a server which is not Nextcloud may answer with are covered with ``MockRequesting`` in ``LoginRequestTests``.
///
@Suite("Login") struct LoginTests: ServerTesting {
    @Test("Fetch Login Information", arguments: ServerVersion.allCases)
    func fetchLoginInformation(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let flow = try await server.login()

        #expect(flow.endpoint.path.hasSuffix("/login/v2/poll"))
        #expect(flow.entry.path.contains("/login/v2/flow/"))
        #expect(flow.token.isEmpty == false)
    }
}
