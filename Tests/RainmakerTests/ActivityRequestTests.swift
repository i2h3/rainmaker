// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` builds its request and how it reads the server's response beyond the body.
///
/// These tests deliberately do not use the fixture tree: ``FixtureLocator`` keys fixtures by HTTP method and URL path only, so a replayed test still finds its fixture when the query string is wrong or missing entirely and therefore cannot prove anything about it. A capturing ``MockRequesting`` is used instead, which also makes it possible to serve statuses a live baseline cannot be made to produce.
///
@Suite("Activity Requests") struct ActivityRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// An OCS envelope with an empty activity list, enough for the call to succeed so the captured request can be inspected.
    ///
    let emptyEnvelope = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[]}}"#

    ///
    /// Run one activity request against a capturing mock and return the query items it produced, keyed by name, together with the requested path.
    ///
    private func capture(filter: String = ActivityFilter.all, since: Int = 0, limit: Int = 50, sort: ActivitySort = .newestFirst, previews: Bool = false, objectType: String? = nil, objectId: String? = nil) async throws -> (path: String, query: [String: String]) {
        let session = MockRequesting(string: emptyEnvelope)
        let server = Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
        _ = try await server.activities(filter: filter, since: since, limit: limit, sort: sort, previews: previews, objectType: objectType, objectId: objectId)

        let request = try #require(session.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        let query = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        return (components.path, query)
    }

    @Test("Default Request Carries The Server's Own Defaults")
    func defaultRequest() async throws {
        let (path, query) = try await capture()

        #expect(path == "/ocs/v2.php/apps/activity/api/v2/activity/all")
        #expect(query["since"] == "0")
        #expect(query["limit"] == "50")
        #expect(query["sort"] == "desc")

        // Previews are opt-in, so the parameter is omitted rather than sent as false.
        #expect(query["previews"] == nil)
        #expect(query["object_type"] == nil)
        #expect(query["object_id"] == nil)
    }

    @Test("Arguments Reach The Query")
    func arguments() async throws {
        let (path, query) = try await capture(filter: ActivityFilter.own, since: 24, limit: 10, sort: .oldestFirst, previews: true)

        #expect(path == "/ocs/v2.php/apps/activity/api/v2/activity/self")
        #expect(query["since"] == "24")
        #expect(query["limit"] == "10")
        #expect(query["sort"] == "asc")
        #expect(query["previews"] == "true")
    }

    @Test("Naming An Object Selects The Object Filter")
    func objectFilter() async throws {
        let (path, query) = try await capture(filter: ActivityFilter.all, objectType: "files", objectId: "72")

        // The object pair overrides the given filter because narrowing to one object is a filter of its own on the server.
        #expect(path == "/ocs/v2.php/apps/activity/api/v2/activity/filter")
        #expect(query["object_type"] == "files")
        #expect(query["object_id"] == "72")
    }

    @Test("A Half Given Object Is Ignored")
    func incompleteObject() async throws {
        let (path, query) = try await capture(objectType: "files", objectId: nil)

        // The server requires both, so naming only one must not switch the filter or send a lone parameter.
        #expect(path == "/ocs/v2.php/apps/activity/api/v2/activity/all")
        #expect(query["object_type"] == nil)
        #expect(query["object_id"] == nil)
    }

    @Test("Page Size Is Clamped To What The Server Accepts", arguments: [(0, "1"), (-5, "1"), (1, "1"), (500, "500"), (501, "500"), (10000, "500")])
    func limitClamping(_ limit: Int, _ expected: String) async throws {
        let (_, query) = try await capture(limit: limit)

        // Outside of one to five hundred the server answers with an internal error rather than a validation error.
        #expect(query["limit"] == expected)
    }

    @Test("No Content Is An Empty Page Rather Than An Error")
    func noContent() async throws {
        // The server answers with no content when the account has every activity type switched off.
        let session = MockRequesting(string: "", statusCode: 204, headerFields: ["X-Activity-First-Known": "73"])
        let server = Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
        let page = try await server.activities(filter: ActivityFilter.all, since: 0, limit: 50, sort: .newestFirst, previews: false, objectType: nil, objectId: nil)

        #expect(page.items.isEmpty)
        #expect(page.firstKnown == 73)
        #expect(page.lastGiven == nil)
    }

    @Test("Not Modified Is An Empty Page Rather Than An Error")
    func notModified() async throws {
        let session = MockRequesting(string: "", statusCode: 304, headerFields: ["X-Activity-First-Known": "73"])
        let server = Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
        let page = try await server.activities(filter: ActivityFilter.all, since: 1, limit: 50, sort: .newestFirst, previews: false, objectType: nil, objectId: nil)

        #expect(page.items.isEmpty)
        #expect(page.firstKnown == 73)
    }

    @Test("Cursors Are Read From The Response Headers")
    func cursors() async throws {
        let session = MockRequesting(string: emptyEnvelope, headerFields: ["X-Activity-First-Known": "73", "X-Activity-Last-Given": "24"])
        let server = Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
        let page = try await server.activities(filter: ActivityFilter.all, since: 0, limit: 50, sort: .newestFirst, previews: false, objectType: nil, objectId: nil)

        #expect(page.firstKnown == 73)
        #expect(page.lastGiven == 24)
    }
}
