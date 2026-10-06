// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About the request ``Server/currentUser()`` sends and how it maps the statuses and bodies a server answers with onto a ``User`` and ``RainmakerError``.
///
/// These tests deliberately do not use the fixture tree: a live Nextcloud server cannot be made to reject the credentials of the recording account, to fail an OCS request with a success status or to answer with something other than JSON, and a replayed fixture proves neither the request headers nor the cancellation. The replayed counterpart is ``CurrentUserTests``.
///
@Suite("Current User Requests") struct CurrentUserRequestTests {
    ///
    /// The address of the server the tests look up the current user on.
    ///
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// A response body with the details of an account whose identifier differs from its login name, as a server sends it for an account backed by an LDAP directory, reduced to the fields around those ``CurrentUserResponse`` decodes.
    ///
    let payload = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"enabled":true,"id":"5f2b9c1e-4a7d","lastLogin":1788879440000,"quota":{"free":-3,"used":0,"total":-3,"relative":0,"quota":-3},"email":"jane@example.com","displayname":"Jane Doe","display-name":"Jane Doe","groups":["admin"]}}}"#

    ///
    /// Build a server authenticating with an email address as its login name, whose session is the given mock.
    ///
    private func makeServer(session: any Requesting) -> Server {
        Server(address: serverAddress, password: "secret", user: "jane@example.com", session: session, userAgent: "RainmakerTests")
    }

    @Test("Returns The Identifier Rather Than The Login Name")
    func returnsIdentifier() async throws {
        let session = MockRequesting(string: payload, headerFields: ["Content-Type": "application/json; charset=utf-8"])
        let user = try await makeServer(session: session).currentUser()
        let request = try #require(session.requests.first)
        let expectedAuthorization = "Basic \(Data("jane@example.com:secret".utf8).base64EncodedString())"

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/ocs/v2.php/cloud/user")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true")
        #expect(request.value(forHTTPHeaderField: "Authorization") == expectedAuthorization)
        #expect(user == User(id: "5f2b9c1e-4a7d", displayName: "Jane Doe"))
    }

    @Test("Rejected Credentials Report The Status")
    func rejectedCredentials() async throws {
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":997,"message":"Current user is not logged in"},"data":[]}}"#
        let session = MockRequesting(string: body, statusCode: 401)

        await #expect(throws: RainmakerError.unexpectedStatus(code: 401)) {
            _ = try await makeServer(session: session).currentUser()
        }
    }

    @Test("A Missing Route Reports The Status")
    func missingRoute() async throws {
        let session = MockRequesting(string: "<!DOCTYPE html><html></html>", statusCode: 404, headerFields: ["Content-Type": "text/html"])

        await #expect(throws: RainmakerError.unexpectedStatus(code: 404)) {
            _ = try await makeServer(session: session).currentUser()
        }
    }

    @Test("Something Other Than Account Details Fails To Decode")
    func undecodableBody() async throws {
        let session = MockRequesting(string: "<!DOCTYPE html><html></html>", headerFields: ["Content-Type": "text/html"])

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "The server did not answer with the details of the current user.")) {
            _ = try await makeServer(session: session).currentUser()
        }
    }

    @Test("A Failed OCS Request Fails To Decode")
    func failedOCSRequest() async throws {
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":100,"message":"Broken"},"data":{"id":"admin","displayname":"admin"}}}"#
        let session = MockRequesting(string: body)

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "OCS request failed (100): Broken")) {
            _ = try await makeServer(session: session).currentUser()
        }
    }

    @Test("Cancelling The Task Cancels The Request")
    func cancellation() async throws {
        let session = SuspendingRequesting(answering: 0, through: MockRequesting(string: payload))
        let server = makeServer(session: session)

        let lookup = Task {
            try await server.currentUser()
        }

        // The request runs within the calling task, so a Shortcuts action which is stopped ends the lookup at once.
        #expect(try await eventually { session.suspendedCount == 1 })
        lookup.cancel()

        let result = await lookup.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(try await eventually { session.suspendedCount == 0 })
    }
}
