// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/collectives()`` and ``Server/pages(inCollective:)`` build their requests and how they decode what the server answers with.
///
/// These tests deliberately do not use the fixture tree: it is keyed by HTTP method and URL path only, so a replayed test cannot prove what a request carried beyond its path, and a live container cannot be made to produce the responses which matter most here. A capturing ``MockRequesting`` is used instead, which serves the responses of a server without the collectives app, of a collective which does not exist, of a failed OCS envelope and of payloads carrying fields this library does not model.
///
/// The happy paths against a real server are covered by ``CollectivesTests``.
///
@Suite("Collective Requests") struct CollectivesRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// The response of an account without a single collective, enough for a call to succeed so the captured request can be inspected.
    ///
    let noCollectives = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"collectives":[]}}}"#

    ///
    /// The response of a collective without a single page, enough for a call to succeed so the captured request can be inspected.
    ///
    let noPages = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"pages":[]}}}"#

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: MockRequesting) -> Server {
        Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
    }

    ///
    /// Build a server answering every request with the given body and status.
    ///
    private func makeServer(body: String, statusCode: Int = 200) -> Server {
        makeServer(session: MockRequesting(string: body, statusCode: statusCode))
    }

    ///
    /// Return the path and the query items of the single request the given mock captured, keyed by name.
    ///
    private func captured(from session: MockRequesting) throws -> (path: String, query: [String: String]) {
        let request = try #require(session.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        let query = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        return (components.path, query)
    }

    // MARK: - Request Construction

    @Test("Collective Listing Targets The Collectives Endpoint")
    func collectivesPath() async throws {
        let session = MockRequesting(string: noCollectives)
        _ = try await makeServer(session: session).collectives()

        let (path, query) = try captured(from: session)

        #expect(path == "/ocs/v2.php/apps/collectives/api/v1.0/collectives")

        // The endpoint is parameterized through its path alone, so no query parameter is sent at all.
        #expect(query.isEmpty)
    }

    @Test("Page Listing Carries The Collective In Its Path")
    func pagesPath() async throws {
        let session = MockRequesting(string: noPages)
        _ = try await makeServer(session: session).pages(inCollective: 7)

        let (path, query) = try captured(from: session)

        // The identifier belongs in the path rather than in a query, which is what makes it part of the fixture location as well.
        #expect(path == "/ocs/v2.php/apps/collectives/api/v1.0/collectives/7/pages")
        #expect(query.isEmpty)
    }

    @Test("Request Is An Authenticated OCS Request")
    func requestHeaders() async throws {
        let session = MockRequesting(string: noCollectives)
        _ = try await makeServer(session: session).collectives()

        let request = try #require(session.requests.first)
        let headers = request.allHTTPHeaderFields

        #expect(request.httpMethod == "GET")
        #expect(headers?["Accept"] == "application/json")
        #expect(headers?["User-Agent"] == "RainmakerTests")
        #expect(headers?["Authorization"] == "Basic \(Data("admin:admin".utf8).base64EncodedString())")

        // Unlike the notes API this one is reachable through OCS, so the header announcing that has to be sent.
        #expect(headers?["OCS-APIRequest"] == "true")
    }

    // MARK: - Credentials

    @Test("Collective Listing Requires Credentials")
    func requireCredentials() async throws {
        let session = MockRequesting(string: noCollectives)
        let server = Server(address: serverAddress, password: nil, user: nil, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.collectives()
        }

        // Credentials are required, so the call fails before any network request is made.
        #expect(session.requests.isEmpty)
    }

    @Test("Page Listing Requires Credentials")
    func requirePagesCredentials() async throws {
        let session = MockRequesting(string: noPages)
        let server = Server(address: serverAddress, password: nil, user: nil, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.pages(inCollective: 1)
        }

        #expect(session.requests.isEmpty)
    }

    // MARK: - Availability

    @Test("Unavailable App Is Not Found")
    func unavailableApp() async throws {
        // Without the collectives app installed and enabled the OCS route does not exist, which the server reports with an envelope of its own rather than with the app's.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":998,"message":"Invalid query, please check the syntax."},"data":[]}}"#
        let server = makeServer(body: body, statusCode: 404)

        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.collectives()
        }
    }

    @Test("Unknown Collective Is Not Found")
    func unknownCollective() async throws {
        // A collective which does not exist, or which this account cannot reach, is answered with the very same status as an absent app, which is why the two are deliberately not told apart.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":404,"message":"Collective not found: 999"},"data":[]}}"#
        let server = makeServer(body: body, statusCode: 404)

        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.pages(inCollective: 999)
        }
    }

    @Test("Unexpected Status Is Reported As One")
    func forbidden() async throws {
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":403,"message":"Not permitted"},"data":[]}}"#
        let server = makeServer(body: body, statusCode: 403)

        // The app being installed but not permitted for this account is not the same as it being absent, so it must not collapse into a not found error.
        await #expect(throws: RainmakerError.unexpectedStatus(code: 403)) {
            _ = try await server.collectives()
        }
    }

    @Test("Failed OCS Envelope Is A Decoding Failure")
    func failedEnvelope() async throws {
        // A success status carrying a failed envelope is what OCS answers with in some error cases, so the envelope's own status has to be checked rather than trusted.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":500,"message":"Something went wrong"},"data":{"collectives":[]}}}"#
        let server = makeServer(body: body)

        await #expect {
            _ = try await server.collectives()
        } throws: { error in
            guard case let RainmakerError.responseDecodingFailed(reason: reason) = error else {
                return false
            }

            return reason.contains("500") && reason.contains("Something went wrong")
        }
    }

    // MARK: - Decoding

    @Test("Collectives Decode From What A Live Server Sends")
    func decodesCollective() async throws {
        // Verbatim what a live server sends, which is more than the API documents: `userNotify` is not in the published specification at all and must be ignored rather than break the listing.
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"collectives":[{"id":1,"slug":"Corporate","circleId":"vDOFtMFKA9zMxtLm4ARcNEqfH944PCy","emoji":"✨","trashTimestamp":null,"pageMode":0,"name":"Corporate","level":9,"editPermissionLevel":1,"sharePermissionLevel":1,"canEdit":true,"canShare":true,"shareToken":null,"isPageShare":false,"sharePageId":0,"shareEditable":false,"userPageOrder":0,"userShowMembers":true,"userShowRecentPages":true,"userFavoritePages":[],"userNotify":1,"canLeave":true}]}}}"#
        let collective = try #require(try await makeServer(body: body).collectives().first)

        #expect(collective.id == 1)
        #expect(collective.name == "Corporate")
        #expect(collective.slug == "Corporate")
        #expect(collective.emoji == "✨")
        #expect(collective.teamId == "vDOFtMFKA9zMxtLm4ARcNEqfH944PCy")
        #expect(collective.canEdit)
        #expect(collective.canShare)
        #expect(collective.canLeave)
        #expect(collective.shareToken == nil)
        #expect(collective.description == "Corporate")

        // The raw `9` the server sends is meaningless on its own, which is the whole reason the level is modelled as a case.
        #expect(collective.level == .owner)
    }

    @Test("Absent Optionals Decode As Nothing")
    func decodesNullOptionals() async throws {
        // A collective which is not shared, carries no emoji and predates slugs sends explicit nulls rather than omitting the keys.
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"collectives":[{"id":4,"slug":null,"circleId":"abc","emoji":null,"pageMode":0,"name":"Plain","level":1,"editPermissionLevel":1,"sharePermissionLevel":1,"canEdit":false,"canShare":false,"shareToken":null,"canLeave":true}]}}}"#
        let collective = try #require(try await makeServer(body: body).collectives().first)

        #expect(collective.slug == nil)
        #expect(collective.emoji == nil)
        #expect(collective.shareToken == nil)
        #expect(collective.level == .member)
        #expect(collective.canEdit == false)
    }

    @Test("Unknown Membership Level Does Not Fail The Listing")
    func unknownMembershipLevel() async throws {
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"collectives":[{"id":5,"circleId":"abc","pageMode":0,"name":"Future","level":99,"editPermissionLevel":1,"sharePermissionLevel":1,"canEdit":true,"canShare":true,"canLeave":true}]}}}"#
        let collective = try #require(try await makeServer(body: body).collectives().first)

        // A level introduced by a future server must not make a whole collective undecodable.
        #expect(collective.level == .other(99))
    }

    @Test("Pages Decode From What A Live Server Sends")
    func decodesPages() async throws {
        // Verbatim what a live server sends for a collective with a landing page and two subpages.
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"pages":[{"id":116,"slug":"","lastUserId":"admin","lastUserDisplayName":"admin","emoji":null,"subpageOrder":[132,131],"isFullWidth":false,"tags":[],"trashTimestamp":null,"title":"Startseite","timestamp":1700000000,"size":539,"fileName":"Readme.md","filePath":"","filePathString":"","collectivePath":".Kollektive\/Corporate","collectiveNameWithEmoji":null,"parentId":0,"shareToken":null,"linkedPageIds":[]},{"id":131,"slug":"Egy","lastUserId":"admin","lastUserDisplayName":"admin","emoji":null,"subpageOrder":[],"isFullWidth":true,"tags":[3],"trashTimestamp":null,"title":"Egy","timestamp":1600000000,"size":4,"fileName":"Egy.md","filePath":"Recipes","filePathString":"Recipes","collectivePath":".Kollektive\/Corporate","collectiveNameWithEmoji":null,"parentId":116,"shareToken":null,"linkedPageIds":[132]}]}}}"#
        let pages = try await makeServer(body: body).pages(inCollective: 1)

        #expect(pages.count == 2)

        // The server order is preserved, which puts the page at the root of the collective first.
        #expect(pages.map(\.id) == [116, 131])

        let landing = try #require(pages.first { $0.title == "Startseite" })

        // The page at the root reports no parent, which is what `isLandingPage` stands for so a caller does not have to know that zero means this.
        #expect(landing.parentId == 0)
        #expect(landing.isLandingPage)
        #expect(landing.fileName == "Readme.md")
        #expect(landing.filePath.isEmpty)
        #expect(landing.collectivePath == ".Kollektive/Corporate")
        #expect(landing.size == 539)
        #expect(landing.lastEditor == "admin")
        #expect(landing.lastEditorDisplayName == "admin")

        // Pins the conversion of the server's whole seconds since the Unix epoch.
        #expect(landing.modification == Date(timeIntervalSince1970: 1_700_000_000))

        // Not necessarily complete, and deliberately passed on in the server's order rather than sorted.
        #expect(landing.subpageOrder == [132, 131])

        let subpage = try #require(pages.first { $0.title == "Egy" })

        #expect(subpage.isLandingPage == false)
        #expect(subpage.parentId == 116)
        #expect(subpage.slug == "Egy")
        #expect(subpage.filePath == "Recipes")
        #expect(subpage.isFullWidth)
        #expect(subpage.tags == [3])
        #expect(subpage.linkedPageIds == [132])
        #expect(subpage.modification == Date(timeIntervalSince1970: 1_600_000_000))
    }

    @Test("Malformed Success Response Is A Decoding Failure")
    func malformedResponse() async throws {
        let server = makeServer(body: "<!DOCTYPE html><html><body>Log in</body></html>")

        await #expect {
            _ = try await server.collectives()
        } throws: { error in
            error is DecodingError
        }
    }
}
