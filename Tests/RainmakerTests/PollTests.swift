// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// Login flow related tests.
///
@Suite("Polling") struct PollTests: ServerTesting {
    let token = "some-token"

    @Test("Polling Failure", arguments: ServerVersion.allCases)
    func pollingFailure(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let endpoint = serverAddress.appending(components: "index.php", "login", "v2", "poll")

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "The server returned no login flow result on polling.")) {
            _ = try await server.poll(endpoint, token: token)
        }
    }

    @Test("Polling Success", arguments: ServerVersion.allCases)
    func pollingSuccess(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let endpoint = serverAddress.appending(components: "index.php", "login", "v2", "poll")

        await #expect(throws: Never.self) {
            _ = try await server.poll(endpoint, token: token)
        }
    }
}
