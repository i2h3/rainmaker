// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/login()`` and ``Server/poll(_:)`` map the statuses and bodies a server answers with onto their results and ``RainmakerError``, and how the deprecated ``Server/poll(_:token:)`` keeps its behaviour.
///
/// These tests deliberately do not use the fixture tree: a live Nextcloud server cannot be made to answer with an HTML page, a missing endpoint or a server error, and ``URLTestSession`` does not look at request bodies. The replayed counterparts are in ``LoginTests`` and ``PollTests``. A capturing ``MockRequesting`` is used instead.
///
@Suite("Login Requests") struct LoginRequestTests {
    ///
    /// The address of the server the tests begin login flows on.
    ///
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// A response body with a login flow as a Nextcloud server sends it when a flow begins.
    ///
    let flowPayload = #"{"poll":{"token":"pollToken123","endpoint":"http:\/\/localhost\/login\/v2\/poll"},"login":"http:\/\/localhost\/login\/v2\/flow\/loginToken456"}"#

    ///
    /// A response body with the credentials of a completed login flow as a Nextcloud server sends them.
    ///
    let resultPayload = #"{"server":"http:\/\/localhost","loginName":"admin@example.com","appPassword":"secret"}"#

    ///
    /// A response body as a web server which is not Nextcloud answers with, which ``Server/login()`` must not take for a login flow.
    ///
    let htmlPayload = "<!DOCTYPE html><html><head><title>Welcome</title></head><body>It works!</body></html>"

    ///
    /// The login flow the polling tests check, as ``Server/login()`` would have returned it for ``flowPayload``.
    ///
    let flow = LoginFlow(endpoint: URL(string: "http://localhost/login/v2/poll")!, entry: URL(string: "http://localhost/login/v2/flow/loginToken456")!, token: "pollToken123")

    ///
    /// Build a server without credentials whose session is the given mock, as a client beginning a login has no credentials yet.
    ///
    private func makeServer(session: any Requesting) -> Server {
        Server(address: serverAddress, session: session, userAgent: "RainmakerTests")
    }

    // MARK: - Beginning

    @Test("Beginning Returns The Login Flow")
    func beginReturnsFlow() async throws {
        let session = MockRequesting(string: flowPayload)
        let flow = try await makeServer(session: session).login()
        let request = try #require(session.requests.first)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/index.php/login/v2")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(flow == self.flow)
    }

    @Test("Beginning On Something Other Than Nextcloud Fails To Decode")
    func beginOnHTML() async throws {
        let session = MockRequesting(string: htmlPayload, headerFields: ["Content-Type": "text/html"])

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "The server did not answer with a login flow, so it is probably not a Nextcloud server.")) {
            _ = try await makeServer(session: session).login()
        }
    }

    @Test("Beginning On A Missing Endpoint Is Not Found")
    func beginOnMissingEndpoint() async throws {
        let session = MockRequesting(string: htmlPayload, statusCode: 404, headerFields: ["Content-Type": "text/html"])

        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).login()
        }
    }

    @Test("Beginning On A Failing Server Reports The Status")
    func beginOnFailingServer() async throws {
        let session = MockRequesting(string: "", statusCode: 500)

        await #expect(throws: RainmakerError.unexpectedStatus(code: 500)) {
            _ = try await makeServer(session: session).login()
        }
    }

    // MARK: - Polling

    @Test("Polling Posts The Token As A Form Field")
    func pollPostsToken() async throws {
        let session = MockRequesting(string: "[]", statusCode: 404)
        _ = try await makeServer(session: session).poll(flow)
        let request = try #require(session.requests.first)
        let body = try #require(request.httpBody)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url == flow.endpoint)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(String(decoding: body, as: UTF8.self) == "token=pollToken123")
    }

    @Test("Polling Encodes The Token")
    func pollEncodesToken() async throws {
        let session = MockRequesting(string: "[]", statusCode: 404)
        let flow = LoginFlow(endpoint: flow.endpoint, entry: flow.entry, token: "a+b&c=d")
        _ = try await makeServer(session: session).poll(flow)
        let body = try #require(session.requests.first?.httpBody)

        #expect(String(decoding: body, as: UTF8.self) == "token=a%2Bb%26c%3Dd")
    }

    @Test("Polling A Pending Flow Returns Nil")
    func pollPending() async throws {
        let session = MockRequesting(string: "[]", statusCode: 404, headerFields: ["Content-Type": "application/json; charset=utf-8"])
        let result = try await makeServer(session: session).poll(flow)

        #expect(result == nil)
    }

    @Test("Polling A Completed Flow Returns The Result")
    func pollCompleted() async throws {
        let session = MockRequesting(string: resultPayload)
        let result = try await makeServer(session: session).poll(flow)

        // The login name is kept as the user typed it, which is not necessarily the identifier of the account.
        #expect(try result == LoginResult(name: "admin@example.com", password: "secret", server: #require(URL(string: "http://localhost"))))
    }

    @Test("Polling A Missing Endpoint Is Not Found")
    func pollMissingEndpoint() async throws {
        let session = MockRequesting(string: htmlPayload, statusCode: 404, headerFields: ["Content-Type": "text/html"])

        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).poll(flow)
        }
    }

    @Test("Polling A Failing Server Reports The Status")
    func pollFailingServer() async throws {
        let session = MockRequesting(string: "", statusCode: 503)

        await #expect(throws: RainmakerError.unexpectedStatus(code: 503)) {
            _ = try await makeServer(session: session).poll(flow)
        }
    }

    @Test("Polling Something Other Than Credentials Fails To Decode")
    func pollUndecodable() async throws {
        let session = MockRequesting(string: htmlPayload, headerFields: ["Content-Type": "text/html"])

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "The server did not answer with the result of the login flow.")) {
            _ = try await makeServer(session: session).poll(flow)
        }
    }

    @Test("Cancelling A Poll Cancels Its Request")
    func cancelPoll() async throws {
        let session = SuspendingRequesting(answering: 0, through: MockRequesting(string: "[]", statusCode: 404))
        let server = makeServer(session: session)

        let polling = Task {
            try await server.poll(flow)
        }

        // The request runs within the calling task, so a login sheet which is dismissed stops polling at once.
        #expect(try await eventually { session.suspendedCount == 1 })
        polling.cancel()

        let result = await polling.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(try await eventually { session.suspendedCount == 0 })
    }

    // MARK: - Deprecated Polling

    @Test("Deprecated Polling Still Throws While Pending")
    func deprecatedPollPending() async throws {
        let session = MockRequesting(string: "[]", statusCode: 404)
        let server: any Serving = makeServer(session: session)

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "The server returned no login flow result on polling.")) {
            _ = try await server.poll(flow.endpoint, token: flow.token)
        }

        let body = try #require(session.requests.first?.httpBody)

        #expect(String(decoding: body, as: UTF8.self) == "token=pollToken123")
    }

    @Test("Deprecated Polling Still Returns The Result")
    func deprecatedPollCompleted() async throws {
        let session = MockRequesting(string: resultPayload)
        let server: any Serving = makeServer(session: session)
        let result = try await server.poll(flow.endpoint, token: flow.token)

        #expect(result.name == "admin@example.com")
    }
}
