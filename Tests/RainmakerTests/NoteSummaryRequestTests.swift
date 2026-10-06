// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About ``Server/noteSummaries(changedSince:)``, its conditional and chunked counterparts and ``Server/noteSummaryChunks(changedSince:chunkSize:)``, which list notes without their text.
///
/// These tests drive a capturing ``MockRequesting`` rather than the fixture tree for the reasons ``NoteChangesRequestTests`` gives: a replayed fixture neither proves which query items and request headers were sent, because ``FixtureLocator`` ignores both, nor answers a loop of chunks which share method and path. The recorded counterparts are ``NotesTests/fetchSummaries(_:)`` and ``NotesTests/fetchFirstSummaryChunk(_:)``.
///
@Suite("Note Summary Requests") struct NoteSummaryRequestTests {
    ///
    /// The address of the server the requests in this suite are sent to.
    ///
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// A moment the requests in this suite ask for changes since.
    ///
    let changedSince = Date(timeIntervalSince1970: 1_700_000_000)

    ///
    /// A response body with one note sent in full but for its content and one reduced to its identifier, shaped as the notes app answers a listing which excludes the content.
    ///
    /// The server still sends `error` and `errorType`, always as `false` and empty, because it only notices an error while reading the content it was asked to leave out.
    ///
    let payload = #"[{"id":7,"title":"Changed","modified":1700000000,"category":"Work","favorite":true,"readonly":false,"internalPath":"/Notes/Work/Changed.md","shareTypes":[3],"isShared":true,"error":false,"errorType":"","etag":"9cf1"},{"id":8}]"#

    ///
    /// The headers of a complete listing as the notes app sends them, with the version header every supported response has to carry.
    ///
    let completeHeaders = [
        "X-Notes-API-Versions": "0.2, 1.3, 1.4",
        "ETag": #""c649e503de046daca1b998c2e52b2a94""#,
        "Last-Modified": "Tue, 14 Nov 2023 22:13:20 GMT",
    ]

    ///
    /// The query item every summary listing has to send.
    ///
    let excludeContent = URLQueryItem(name: "exclude", value: "content")

    ///
    /// The query item every listing in this suite sends for ``changedSince``.
    ///
    let pruneBefore = URLQueryItem(name: "pruneBefore", value: "1700000000")

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: any Requesting) -> Server {
        Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
    }

    ///
    /// Read the query items of a captured request.
    ///
    private func queryItems(of request: URLRequest) throws -> [URLQueryItem] {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        return components.queryItems ?? []
    }

    ///
    /// Build a responder which answers a pass of two chunks of summaries, keyed on the cursor each request continues from.
    ///
    private func makeTwoChunkResponder() -> MockRequesting.Responder {
        let headers = completeHeaders

        return { request in
            let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            let cursor = components?.queryItems?.first { $0.name == "chunkCursor" }?.value
            var chunkHeaders = headers
            let body: String

            if cursor == nil {
                body = #"[{"id":1,"etag":"a1","readonly":false,"modified":1700000000,"title":"One","category":"","favorite":false,"error":false,"errorType":""}]"#
                chunkHeaders["X-Notes-Chunk-Cursor"] = "1700000000-1699999001-1"
                chunkHeaders["X-Notes-Chunk-Pending"] = "1"
            } else {
                body = #"[{"id":2,"etag":"a2","readonly":true,"modified":1700000000,"title":"Two","category":"","favorite":false,"error":false,"errorType":""},{"id":1},{"id":3}]"#
            }

            return (Data(body.utf8), 200, chunkHeaders)
        }
    }

    // MARK: - Query

    @Test("A Summary Listing Asks To Exclude The Content And Nothing Else")
    func excludesContent() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        _ = try await makeServer(session: session).noteSummaries(changedSince: changedSince)

        let request = try #require(session.requests.first)
        let url = try #require(request.url)

        // The title in particular is never excluded, because its presence is what tells a note sent in full from one reduced to its identifier.
        #expect(try queryItems(of: request) == [pruneBefore, excludeContent])
        #expect(url.path == "/index.php/apps/notes/api/v1/notes")
        #expect(request.httpMethod == "GET")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("Every Summary Listing Asks To Exclude The Content")
    func everyVariantExcludesContent() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let server = makeServer(session: session)

        _ = try await server.noteSummaries(changedSince: changedSince, ifChangedFrom: #"W/"c649e503de046daca1b998c2e52b2a94""#)
        _ = try await server.noteSummaries(changedSince: changedSince, chunkSize: 0)
        _ = try await server.noteSummaries(changedSince: changedSince, chunkSize: 25, continuingAfter: "1700000000-1699999999-7")
        _ = try await server.noteSummaries(changedSince: changedSince, chunkSize: 25, ifChangedFrom: "c649e503de046daca1b998c2e52b2a94")

        let requests = session.requests
        try #require(requests.count == 4)

        #expect(try queryItems(of: requests[0]) == [pruneBefore, excludeContent])
        #expect(try queryItems(of: requests[1]) == [pruneBefore, excludeContent, URLQueryItem(name: "chunkSize", value: "1")])
        #expect(try queryItems(of: requests[2]) == [pruneBefore, excludeContent, URLQueryItem(name: "chunkSize", value: "25"), URLQueryItem(name: "chunkCursor", value: "1700000000-1699999999-7")])
        #expect(try queryItems(of: requests[3]) == [pruneBefore, excludeContent, URLQueryItem(name: "chunkSize", value: "25")])

        // The conditional variants normalize the tag as the listings of notes with their text do.
        #expect(requests[0].value(forHTTPHeaderField: "If-None-Match") == #""c649e503de046daca1b998c2e52b2a94""#)
        #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(requests[3].value(forHTTPHeaderField: "If-None-Match") == #""c649e503de046daca1b998c2e52b2a94""#)
    }

    @Test("A Listing Of Notes With Their Text Never Asks To Exclude Anything")
    func notesDoNotExclude() async throws {
        let fullPayload = #"[{"id":7,"etag":"9cf1","readonly":false,"modified":1700000000,"title":"Changed","category":"","content":"text","favorite":false,"error":false,"errorType":""},{"id":8}]"#
        let session = MockRequesting(string: fullPayload, headerFields: completeHeaders)
        let server = makeServer(session: session)

        _ = try await server.notes(changedSince: changedSince)
        _ = try await server.notes(changedSince: changedSince, ifChangedFrom: "c649e503")
        _ = try await server.notes(changedSince: changedSince, chunkSize: 25, continuingAfter: nil)
        _ = try await server.notes(changedSince: changedSince, chunkSize: 25, ifChangedFrom: "c649e503")

        // A note decodes only with its content, so the listings returning notes must keep asking for it.
        for request in session.requests {
            #expect(try queryItems(of: request).contains { $0.name == "exclude" } == false)
        }

        #expect(session.requests.count == 4)
    }

    // MARK: - Decoding

    @Test("Decodes Summaries Alongside Identifiers And Reads The Headers")
    func decodesMixedEntries() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let changes = try await makeServer(session: session).noteSummaries(changedSince: changedSince)

        let expected = NoteSummary(id: 7, entityTag: "9cf1", title: "Changed", category: "Work", isFavorite: true, modification: Date(timeIntervalSince1970: 1_700_000_000), path: "/Notes/Work/Changed.md", isShared: true, shareTypes: [.link])

        #expect(changes.changed == [expected])
        #expect(changes.unchanged == [8])
        #expect(changes.lastModified == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(changes.entityTag == "c649e503de046daca1b998c2e52b2a94")
        #expect(changes.chunkCursor == nil)
        #expect(changes.pendingCount == nil)
        #expect(changes.isComplete)
    }

    @Test("A Response Which Carries The Content After All Still Decodes")
    func ignoresContent() async throws {
        let withContent = #"[{"id":7,"etag":"9cf1","readonly":true,"modified":1700000000,"title":"Changed","category":"","content":"Error: OCP\\Files\\NotPermittedException","favorite":false,"error":true,"errorType":"OCP\\Files\\NotPermittedException"}]"#
        let changes = try await makeServer(session: MockRequesting(string: withContent, headerFields: completeHeaders)).noteSummaries(changedSince: changedSince)

        // A summary has no place for the content or the error, so a server or proxy which sends them anyway does not fail the call.
        #expect(changes.changed.map(\.id) == [7])
        #expect(changes.changed.first?.isReadOnly == true)
        #expect(changes.unchanged.isEmpty)
    }

    @Test("A Summary Without An Entity Tag Fails To Decode")
    func malformedSummary() async throws {
        let malformed = #"[{"id":7,"readonly":false,"modified":1700000000,"title":"Changed","category":"","favorite":false}]"#
        let server = makeServer(session: MockRequesting(string: malformed, headerFields: completeHeaders))

        // The presence of the title marks a note sent in full, so one which lacks a required field is reported rather than taken for an unchanged one.
        await #expect {
            _ = try await server.noteSummaries(changedSince: changedSince)
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("Reads The Chunk Cursor And The Pending Count")
    func readsChunkHeaders() async throws {
        let session = MockRequesting(responder: makeTwoChunkResponder())
        let changes = try await makeServer(session: session).noteSummaries(changedSince: changedSince, chunkSize: 1, continuingAfter: nil)

        #expect(changes.changed.map(\.title) == ["One"])
        #expect(changes.unchanged.isEmpty)
        #expect(changes.chunkCursor == "1700000000-1699999001-1")
        #expect(changes.pendingCount == 1)
        #expect(changes.isComplete == false)
    }

    // MARK: - Conditional Requests

    @Test("Not Modified Is Reported As Nil")
    func notModified() async throws {
        let session = MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])
        let server = makeServer(session: session)

        // Nil rather than empty changes, which would claim that every note was deleted.
        let single = try await server.noteSummaries(changedSince: changedSince, ifChangedFrom: "c649e503de046daca1b998c2e52b2a94")
        let chunk = try await server.noteSummaries(changedSince: changedSince, chunkSize: 10, ifChangedFrom: "c649e503de046daca1b998c2e52b2a94")

        #expect(single == nil)
        #expect(chunk == nil)
        #expect(session.requests.count == 2)
    }

    @Test("Not Modified Is Unexpected For An Unconditional Request")
    func notModifiedUnconditionally() async throws {
        let server = makeServer(session: MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"]))

        await #expect(throws: RainmakerError.unexpectedStatus(code: 304)) {
            _ = try await server.noteSummaries(changedSince: changedSince)
        }

        await #expect(throws: RainmakerError.unexpectedStatus(code: 304)) {
            _ = try await server.noteSummaries(changedSince: changedSince, chunkSize: 10, continuingAfter: "1700000000-1699999999-7")
        }
    }

    @Test("A Changed Response Is Returned In Full")
    func changedResponse() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let changes = try #require(try await makeServer(session: session).noteSummaries(changedSince: changedSince, ifChangedFrom: "stale"))

        #expect(changes.changed.map(\.id) == [7])
        #expect(changes.unchanged == [8])
        #expect(changes.entityTag == "c649e503de046daca1b998c2e52b2a94")
    }

    // MARK: - Statuses

    @Test("Maps Statuses Like The Listings Of Notes With Their Text")
    func statusMapping() async throws {
        let unavailable = makeServer(session: MockRequesting(string: "", statusCode: 404, headerFields: [:]))

        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            _ = try await unavailable.noteSummaries(changedSince: changedSince)
        }

        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            _ = try await unavailable.noteSummaries(changedSince: changedSince, ifChangedFrom: "c649e503")
        }

        let outdated = makeServer(session: MockRequesting(string: "[]", headerFields: ["X-Notes-API-Versions": "0.2, 1.3"]))
        let expected = RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])

        await #expect(throws: expected) {
            _ = try await outdated.noteSummaries(changedSince: changedSince, chunkSize: 10, continuingAfter: nil)
        }
    }

    @Test("Every Summary Listing Requires Credentials")
    func requireCredentials() async throws {
        let session = MockRequesting(responder: makeTwoChunkResponder())
        let server = Server(address: serverAddress, password: nil, user: nil, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.noteSummaries(changedSince: changedSince)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.noteSummaries(changedSince: changedSince, ifChangedFrom: "c649e503")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.noteSummaries(changedSince: changedSince, chunkSize: 1)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.noteSummaries(changedSince: changedSince, chunkSize: 1, ifChangedFrom: "c649e503")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            for try await _ in server.noteSummaryChunks(changedSince: changedSince, chunkSize: 1) {}
        }

        #expect(session.requests.isEmpty)
    }

    // MARK: - Stream Of Chunks

    @Test("The Stream Follows The Cursors Until The Last Chunk")
    func streamFollowsCursors() async throws {
        let session = MockRequesting(responder: makeTwoChunkResponder())
        var chunks = [NoteSummaryChanges]()

        for try await chunk in makeServer(session: session).noteSummaryChunks(changedSince: changedSince, chunkSize: 1) {
            chunks.append(chunk)
        }

        #expect(chunks.map { $0.changed.map(\.id) } == [[1], [2]])
        #expect(chunks.map(\.isComplete) == [false, true])
        #expect(chunks.map(\.unchanged) == [[], [1, 3]])

        // Every chunk of the pass leaves out the content, and each continues from the cursor of the chunk before.
        let requests = session.requests
        #expect(try requests.map { try queryItems(of: $0) } == [
            [pruneBefore, excludeContent, URLQueryItem(name: "chunkSize", value: "1")],
            [pruneBefore, excludeContent, URLQueryItem(name: "chunkSize", value: "1"), URLQueryItem(name: "chunkCursor", value: "1700000000-1699999001-1")],
        ])
    }

    @Test("Cancelling The Stream's Task Cancels The Request In Flight")
    func streamCancelsRequestInFlight() async throws {
        let session = SuspendingRequesting(answering: 1, through: MockRequesting(responder: makeTwoChunkResponder()))
        let server = makeServer(session: session)
        let received = LockedValue(0)

        let consumer = Task {
            for try await _ in server.noteSummaryChunks(changedSince: changedSince, chunkSize: 1) {
                received.withValue { $0 += 1 }
            }
        }

        // The first chunk is answered, while the request for the second one stays in flight until its task is cancelled.
        #expect(try await eventually { session.suspendedCount == 1 })
        consumer.cancel()

        let result = await consumer.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(try await eventually { session.suspendedCount == 0 })
        #expect(received.get() == 1)
        #expect(session.receivedCount == 2)
    }
}
