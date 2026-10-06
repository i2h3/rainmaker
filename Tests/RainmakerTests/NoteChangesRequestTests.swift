// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About what ``Server/notes(changedSince:)`` and ``Server/notes(changedSince:ifChangedFrom:)`` read from the headers of a response, and how the latter asks for and reports a response which did not change.
///
/// These tests deliberately do not use the fixture tree, for the reasons ``NotesRequestTests`` gives: the canonicalized fixtures carry fixed header values only, ``URLTestSession`` ignores request headers, so it cannot prove a conditional request was made, and a test sending the same request twice would find the same fixture both times. A capturing ``MockRequesting`` is used instead.
///
@Suite("Note Changes Requests") struct NoteChangesRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// A moment the requests in this suite ask for changes since.
    ///
    let changedSince = Date(timeIntervalSince1970: 1_700_000_000)

    ///
    /// A response body with one note sent in full and one reduced to its identifier, which is the shape every listing narrowed down by a moment has.
    ///
    let payload = #"[{"id":7,"etag":"9cf1","readonly":false,"modified":1700000000,"title":"Changed","category":"","content":"text","favorite":false,"error":false,"errorType":""},{"id":8}]"#

    ///
    /// The headers of a complete listing as the notes app sends them, with the version header every supported response has to carry.
    ///
    let completeHeaders = [
        "X-Notes-API-Versions": "0.2, 1.3, 1.4",
        "ETag": #""c649e503de046daca1b998c2e52b2a94""#,
        "Last-Modified": "Tue, 14 Nov 2023 22:13:20 GMT",
    ]

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: MockRequesting) -> Server {
        Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
    }

    // MARK: - Headers

    @Test("Reads The Moment And The Entity Tag From The Headers")
    func readsHeaders() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let changes = try await makeServer(session: session).notes(changedSince: changedSince)

        #expect(changes.changed.map(\.id) == [7])
        #expect(changes.unchanged == [8])

        // The moment is the server's own time it started answering, which is what the next call passes back as its moment.
        #expect(changes.lastModified == Date(timeIntervalSince1970: 1_700_000_000))

        // The tag is handed out bare, so it can be passed back without knowing how a header has to quote it.
        #expect(changes.entityTag == "c649e503de046daca1b998c2e52b2a94")

        // A response which was not split into chunks is complete and lists every note the account has.
        #expect(changes.chunkCursor == nil)
        #expect(changes.pendingCount == nil)
        #expect(changes.isComplete)
    }

    @Test("Reads A Weakened Entity Tag Without Its Marker")
    func readsWeakEntityTag() async throws {
        var headers = completeHeaders
        headers["ETag"] = #"W/"c649e503de046daca1b998c2e52b2a94""#

        let changes = try await makeServer(session: MockRequesting(string: payload, headerFields: headers)).notes(changedSince: changedSince)

        // A proxy compressing the response may weaken the tag, but the server only compares the bare value.
        #expect(changes.entityTag == "c649e503de046daca1b998c2e52b2a94")
    }

    @Test("Reads The Chunk Cursor And The Pending Count")
    func readsChunkHeaders() async throws {
        var headers = completeHeaders
        headers["X-Notes-Chunk-Cursor"] = "1700000000-1699999999-7"
        headers["X-Notes-Chunk-Pending"] = "3"

        let changes = try await makeServer(session: MockRequesting(string: payload, headerFields: headers)).notes(changedSince: changedSince)

        // A chunk which is not the last one does not list every note, so deletions must not be derived from it.
        #expect(changes.chunkCursor == "1700000000-1699999999-7")
        #expect(changes.pendingCount == 3)
        #expect(changes.isComplete == false)
    }

    @Test("Absent Or Unreadable Headers Leave Their Values Out")
    func absentHeaders() async throws {
        let headers = ["X-Notes-API-Versions": "0.2, 1.3, 1.4", "Last-Modified": "yesterday", "X-Notes-Chunk-Pending": "many"]
        let changes = try await makeServer(session: MockRequesting(string: payload, headerFields: headers)).notes(changedSince: changedSince)

        // The notes themselves are what a caller cannot do without, so a header it cannot read does not fail the retrieval.
        #expect(changes.changed.count == 1)
        #expect(changes.lastModified == nil)
        #expect(changes.entityTag == nil)
        #expect(changes.pendingCount == nil)
        #expect(changes.isComplete)
    }

    @Test("An Unconditional Request Sends No Entity Tag")
    func unconditionalRequest() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        _ = try await makeServer(session: session).notes(changedSince: changedSince)

        let request = try #require(session.requests.first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    // MARK: - Conditional Request

    @Test("Sends The Entity Tag Quoted", arguments: [
        "c649e503de046daca1b998c2e52b2a94",
        #""c649e503de046daca1b998c2e52b2a94""#,
        #"W/"c649e503de046daca1b998c2e52b2a94""#,
    ])
    func sendsQuotedEntityTag(_ entityTag: String) async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        _ = try await makeServer(session: session).notes(changedSince: changedSince, ifChangedFrom: entityTag)

        let request = try #require(session.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        // The server only answers with not modified when the header repeats its strong tag quoted and exactly, so every shape a caller may hold is normalized to that.
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == #""c649e503de046daca1b998c2e52b2a94""#)
        #expect(request.httpMethod == "GET")
        #expect(components.path == "/index.php/apps/notes/api/v1/notes")
        #expect(components.queryItems == [URLQueryItem(name: "pruneBefore", value: "1700000000")])
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("Not Modified Is Reported As Nil")
    func notModified() async throws {
        // The server answers a matching tag with an empty body and still sends its version header, because the notes app adds it before the server turns the status into not modified.
        let session = MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])
        let changes = try await makeServer(session: session).notes(changedSince: changedSince, ifChangedFrom: "c649e503de046daca1b998c2e52b2a94")

        // Nil rather than empty changes, which would claim that every note was deleted.
        #expect(changes == nil)
    }

    @Test("A Changed Response Is Returned In Full")
    func changedResponse() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let changes = try #require(try await makeServer(session: session).notes(changedSince: changedSince, ifChangedFrom: "stale"))

        #expect(changes.changed.map(\.id) == [7])
        #expect(changes.unchanged == [8])
        #expect(changes.lastModified == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(changes.entityTag == "c649e503de046daca1b998c2e52b2a94")
    }

    @Test("Polling With The Previous Tag Returns Nil Until Something Changes")
    func pollingSequence() async throws {
        let currentTag = #""c649e503de046daca1b998c2e52b2a94""#
        let headerFields = completeHeaders

        // Mirrors how the server decides: the full response when the tag differs from the current one, not modified when it matches.
        let session = MockRequesting { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == currentTag {
                return (Data(), 304, ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])
            }

            return (Data(#"[{"id":7},{"id":8}]"#.utf8), 200, headerFields)
        }

        let server = makeServer(session: session)
        let first = try await server.notes(changedSince: changedSince)
        let entityTag = try #require(first.entityTag)
        let lastModified = try #require(first.lastModified)

        // The server compares the tag against the body it would send rather than against the moment, so passing on both values of the previous result is what a polling client does.
        let second = try await server.notes(changedSince: lastModified, ifChangedFrom: entityTag)

        #expect(first.unchanged == [7, 8])
        #expect(second == nil)
        #expect(session.requests.count == 2)
    }

    @Test("Not Modified Is Unexpected For An Unconditional Request")
    func notModifiedUnconditionally() async throws {
        let server = makeServer(session: MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"]))

        // Without a tag the server has no reason to answer not modified, so such an answer is not something to be passed off as either empty or absent changes.
        await #expect(throws: RainmakerError.unexpectedStatus(code: 304)) {
            _ = try await server.notes(changedSince: changedSince)
        }
    }

    @Test("The Conditional Request Maps Statuses Like The Unconditional One")
    func conditionalStatusMapping() async throws {
        let unavailable = makeServer(session: MockRequesting(string: "", statusCode: 404, headerFields: [:]))

        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            _ = try await unavailable.notes(changedSince: changedSince, ifChangedFrom: "c649e503")
        }

        let outdated = makeServer(session: MockRequesting(string: "[]", headerFields: ["X-Notes-API-Versions": "0.2, 1.3"]))
        let expected = RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])

        await #expect(throws: expected) {
            _ = try await outdated.notes(changedSince: changedSince, ifChangedFrom: "c649e503")
        }
    }

    @Test("The Conditional Request Requires Credentials")
    func conditionalRequiresCredentials() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let server = Server(address: serverAddress, password: nil, user: nil, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.notes(changedSince: changedSince, ifChangedFrom: "c649e503")
        }

        #expect(session.requests.isEmpty)
    }
}
