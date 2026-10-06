// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// Login flow related tests.
///
/// The fixtures are hand-authored, because a successful poll needs a login flow a user completed in a browser.
/// ``Server/poll(_:)`` is covered by ``pollingPending(_:)`` and ``pollingResult(_:)``, while ``pollingFailure(_:)`` and ``pollingSuccess(_:)`` keep covering the unchanged behaviour of the deprecated ``Server/poll(_:token:)``, which they call through ``Serving`` so that its deprecation does not warn.
/// The statuses are covered with ``MockRequesting`` in ``LoginRequestTests``.
///
@Suite("Polling") struct PollTests: ServerTesting {
    ///
    /// The token of the login flow the tests poll, which the replayed fixtures do not depend on.
    ///
    let token = "some-token"

    ///
    /// The endpoint the tests poll, which is where the server's login flows point to.
    ///
    var endpoint: URL {
        serverAddress.appendingCompatibility(component: "index.php").appendingCompatibility(component: "login").appendingCompatibility(component: "v2").appendingCompatibility(component: "poll")
    }

    ///
    /// The login flow the tests poll through ``Server/poll(_:)``, created through its public initializer as a client keeping a flow across launches would.
    ///
    var flow: LoginFlow {
        LoginFlow(endpoint: endpoint, entry: serverAddress.appendingCompatibility(path: "index.php/login/v2/flow/some-login-token", directoryHint: .notDirectory), token: token)
    }

    @Test("Polling Failure", arguments: ServerVersion.allCases)
    func pollingFailure(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "The server returned no login flow result on polling.")) {
            _ = try await server.poll(endpoint, token: token)
        }
    }

    @Test("Polling Success", arguments: ServerVersion.allCases)
    func pollingSuccess(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: Never.self) {
            _ = try await server.poll(endpoint, token: token)
        }
    }

    @Test("Polling A Pending Flow Returns Nil", arguments: ServerVersion.allCases)
    func pollingPending(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let result = try await server.poll(flow)

        #expect(result == nil)
    }

    @Test("Polling A Completed Flow Returns The Result", arguments: ServerVersion.allCases)
    func pollingResult(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let result = try #require(try await server.poll(flow))

        #expect(result.name == "admin")
        #expect(result.password.isEmpty == false)
        #expect(result.server == URL(string: "http://localhost"))
    }
}
