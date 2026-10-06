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

    // MARK: - Chunks

    ///
    /// Read the query items of a captured request, which is where the chunk parameters travel.
    ///
    private func queryItems(of request: URLRequest) throws -> [URLQueryItem] {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        return components.queryItems ?? []
    }

    ///
    /// Read the value of one query item of a captured request, or `nil` when it was not sent.
    ///
    private func queryValue(_ name: String, of request: URLRequest) -> String? {
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

        return components?.queryItems?.first { $0.name == name }?.value
    }

    ///
    /// Build a responder which answers a pass of three chunks the way the notes app does, keyed on the cursor each request continues from.
    ///
    /// The first two chunks carry one note in full each, a cursor and the number of notes still pending, while the last one carries the third note in full and the identifiers of all the others, those sent by the earlier chunks included.
    ///
    private func makeThreeChunkResponder(failingAt failingCursor: String? = nil) -> MockRequesting.Responder {
        let headers = completeHeaders

        return { request in
            let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            let cursor = components?.queryItems?.first { $0.name == "chunkCursor" }?.value

            if let failingCursor, cursor == failingCursor {
                return (Data(#"{"errorType":"Exception"}"#.utf8), 500, ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])
            }

            var chunkHeaders = headers
            let body: String

            switch cursor {
                case nil:
                    body = #"[{"id":1,"etag":"a1","readonly":false,"modified":1700000000,"title":"One","category":"","content":"1","favorite":false,"error":false,"errorType":""}]"#
                    chunkHeaders["X-Notes-Chunk-Cursor"] = "1700000000-1699999001-1"
                    chunkHeaders["X-Notes-Chunk-Pending"] = "2"

                case "1700000000-1699999001-1":
                    body = #"[{"id":2,"etag":"a2","readonly":false,"modified":1700000000,"title":"Two","category":"","content":"2","favorite":false,"error":false,"errorType":""}]"#
                    chunkHeaders["X-Notes-Chunk-Cursor"] = "1700000000-1699999002-2"
                    chunkHeaders["X-Notes-Chunk-Pending"] = "1"

                default:
                    body = #"[{"id":3,"etag":"a3","readonly":false,"modified":1700000000,"title":"Three","category":"","content":"3","favorite":false,"error":false,"errorType":""},{"id":1},{"id":2},{"id":4}]"#
            }

            return (Data(body.utf8), 200, chunkHeaders)
        }
    }

    @Test("The First Chunk Sends The Moment And The Chunk Size Only")
    func firstChunkQuery() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        _ = try await makeServer(session: session).notes(changedSince: changedSince, chunkSize: 25)

        let request = try #require(session.requests.first)
        let url = try #require(request.url)

        // A new pass has nothing to continue from, and a category is never asked for because it would also narrow the identifiers deletions are derived from.
        #expect(try queryItems(of: request) == [URLQueryItem(name: "pruneBefore", value: "1700000000"), URLQueryItem(name: "chunkSize", value: "25")])
        #expect(url.path == "/index.php/apps/notes/api/v1/notes")
        #expect(request.httpMethod == "GET")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("A Following Chunk Sends The Cursor")
    func followingChunkQuery() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        _ = try await makeServer(session: session).notes(changedSince: changedSince, chunkSize: 25, continuingAfter: "1700000000-1699999999-7")

        let request = try #require(session.requests.first)

        // The cursor is handed back exactly as the server sent it, along with the same moment the pass started with.
        #expect(try queryItems(of: request) == [URLQueryItem(name: "pruneBefore", value: "1700000000"), URLQueryItem(name: "chunkSize", value: "25"), URLQueryItem(name: "chunkCursor", value: "1700000000-1699999999-7")])
    }

    @Test("The Chunk Size Is At Least One", arguments: [(0, "1"), (-5, "1"), (Int.min, "1"), (1, "1"), (200, "200")])
    func chunkSizeClamping(_ requested: Int, _ sent: String) async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let server = makeServer(session: session)

        _ = try await server.notes(changedSince: changedSince, chunkSize: requested)
        _ = try await server.notes(changedSince: changedSince, chunkSize: requested, ifChangedFrom: "c649e503")

        // The server takes zero as a request not to split the response at all, which a caller asking for chunks did not ask for.
        #expect(session.requests.count == 2)
        #expect(session.requests.allSatisfy { queryValue("chunkSize", of: $0) == sent })
    }

    @Test("An Unchunked Request Sends No Chunk Parameters")
    func unchunkedQuery() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        _ = try await makeServer(session: session).notes(changedSince: changedSince)

        let request = try #require(session.requests.first)
        #expect(try queryItems(of: request) == [URLQueryItem(name: "pruneBefore", value: "1700000000")])
    }

    @Test("The Conditional First Chunk Sends The Entity Tag Quoted And No Cursor")
    func conditionalFirstChunk() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        let changes = try await makeServer(session: session).notes(changedSince: changedSince, chunkSize: 10, ifChangedFrom: #"W/"c649e503de046daca1b998c2e52b2a94""#)

        let request = try #require(session.requests.first)

        #expect(request.value(forHTTPHeaderField: "If-None-Match") == #""c649e503de046daca1b998c2e52b2a94""#)
        #expect(try queryItems(of: request) == [URLQueryItem(name: "pruneBefore", value: "1700000000"), URLQueryItem(name: "chunkSize", value: "10")])
        #expect(changes?.changed.map(\.id) == [7])
    }

    @Test("The Conditional First Chunk Reports Not Modified As Nil")
    func conditionalFirstChunkNotModified() async throws {
        let session = MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])
        let changes = try await makeServer(session: session).notes(changedSince: changedSince, chunkSize: 10, ifChangedFrom: "c649e503de046daca1b998c2e52b2a94")

        #expect(changes == nil)
    }

    @Test("Not Modified Is Unexpected For An Unconditional Chunk")
    func notModifiedChunk() async throws {
        let server = makeServer(session: MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"]))

        await #expect(throws: RainmakerError.unexpectedStatus(code: 304)) {
            _ = try await server.notes(changedSince: changedSince, chunkSize: 10, continuingAfter: "1700000000-1699999999-7")
        }
    }

    @Test("Chunks Require Credentials")
    func chunksRequireCredentials() async throws {
        let session = MockRequesting(responder: makeThreeChunkResponder())
        let server = Server(address: serverAddress, password: nil, user: nil, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.notes(changedSince: changedSince, chunkSize: 1)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.notes(changedSince: changedSince, chunkSize: 1, ifChangedFrom: "c649e503")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            for try await _ in server.noteChunks(changedSince: changedSince, chunkSize: 1) {}
        }

        #expect(session.requests.isEmpty)
    }

    // MARK: - Stream Of Chunks

    @Test("The Stream Follows The Cursors Until The Last Chunk")
    func streamFollowsCursors() async throws {
        let session = MockRequesting(responder: makeThreeChunkResponder())
        var chunks = [NoteChanges]()

        for try await chunk in makeServer(session: session).noteChunks(changedSince: changedSince, chunkSize: 1) {
            chunks.append(chunk)
        }

        // One element per chunk, in the order the server sent them, finishing after the one which lists every note.
        #expect(chunks.map { $0.changed.map(\.id) } == [[1], [2], [3]])
        #expect(chunks.map(\.isComplete) == [false, false, true])
        #expect(chunks.map(\.pendingCount) == [2, 1, nil])

        // Only the last chunk carries the identifiers, and those of the notes the earlier chunks sent are among them.
        #expect(chunks.map(\.unchanged) == [[], [], [1, 2, 4]])

        // Every request continues from the cursor of the chunk before, with the same moment and chunk size, and none asks for a category.
        let requests = session.requests
        #expect(requests.map { queryValue("chunkCursor", of: $0) } == [nil, "1700000000-1699999001-1", "1700000000-1699999002-2"])
        #expect(requests.allSatisfy { queryValue("pruneBefore", of: $0) == "1700000000" })
        #expect(requests.allSatisfy { queryValue("chunkSize", of: $0) == "1" })
        #expect(requests.allSatisfy { queryValue("category", of: $0) == nil })
    }

    @Test("The Stream Of A Single Chunk Finishes After It")
    func streamSingleChunk() async throws {
        let session = MockRequesting(string: payload, headerFields: completeHeaders)
        var chunks = [NoteChanges]()

        for try await chunk in makeServer(session: session).noteChunks(changedSince: changedSince, chunkSize: 100) {
            chunks.append(chunk)
        }

        // A pass whose changes fit into one chunk consists of nothing but the complete one.
        #expect(chunks.count == 1)
        #expect(chunks.first?.isComplete == true)
        #expect(session.requests.count == 1)
    }

    @Test("The Stream Finishes By Throwing An Error Mid-Pass")
    func streamErrorMidPass() async throws {
        let session = MockRequesting(responder: makeThreeChunkResponder(failingAt: "1700000000-1699999001-1"))
        let chunks = LockedValue([NoteChanges]())

        await #expect(throws: RainmakerError.unexpectedStatus(code: 500)) {
            for try await chunk in makeServer(session: session).noteChunks(changedSince: changedSince, chunkSize: 1) {
                chunks.withValue { $0.append(chunk) }
            }
        }

        // The chunk received before the error stays usable, and its cursor is what continues the pass later.
        #expect(chunks.get().map(\.chunkCursor) == ["1700000000-1699999001-1"])
        #expect(session.requests.count == 2)
    }

    @Test("The Stream Requests Nothing After The Consumer Stops")
    func streamStopsWithConsumer() async throws {
        let session = MockRequesting(responder: makeThreeChunkResponder())

        for try await chunk in makeServer(session: session).noteChunks(changedSince: changedSince, chunkSize: 1) {
            #expect(chunk.isComplete == false)
            break
        }

        // The next chunk is only requested when the consumer asks for it, so leaving the loop leaves the remaining chunks unrequested.
        #expect(session.requests.count == 1)
    }

    @Test("The Stream Requests Nothing After Its Task Was Cancelled")
    func streamStopsWhenCancelled() async {
        let session = MockRequesting(responder: makeThreeChunkResponder())
        let server = makeServer(session: session)

        let consumer = Task {
            var count = 0

            for try await _ in server.noteChunks(changedSince: changedSince, chunkSize: 1) {
                count += 1
                withUnsafeCurrentTask { $0?.cancel() }
            }

            return count
        }

        // A cancellation between two chunks ends the stream quietly, which is why a consumer checks whether the last chunk is complete, and it must not request another chunk either way.
        let result = await consumer.result

        if case let .failure(error) = result {
            #expect(error is CancellationError)
        }

        #expect(session.requests.count == 1)
    }

    @Test("Cancelling The Stream's Task Cancels The Request In Flight")
    func streamCancelsRequestInFlight() async throws {
        let session = SuspendingRequesting(answering: 1, through: MockRequesting(responder: makeThreeChunkResponder()))
        let server = Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
        let received = LockedValue(0)

        let consumer = Task {
            for try await _ in server.noteChunks(changedSince: changedSince, chunkSize: 1) {
                received.withValue { $0 += 1 }
            }
        }

        // The first chunk is answered, while the request for the second one stays in flight until its task is cancelled.
        #expect(try await eventually { session.suspendedCount == 1 })
        consumer.cancel()

        // The request runs within the consumer's task, so cancelling that task ends the request, which then ends the stream.
        let result = await consumer.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(try await eventually { session.suspendedCount == 0 })
        #expect(received.get() == 1)
        #expect(session.receivedCount == 2)
    }

    @Test("The Stream Stops When The Cursor Does Not Advance")
    func streamStopsOnRepeatedCursor() async throws {
        var headers = completeHeaders
        headers["X-Notes-Chunk-Cursor"] = "1700000000-1699999001-1"
        headers["X-Notes-Chunk-Pending"] = "2"

        // A server which ignores the cursor answers every request with the first chunk again, which would never end.
        let session = MockRequesting(string: payload, headerFields: headers)
        let chunks = LockedValue(0)

        await #expect {
            for try await _ in makeServer(session: session).noteChunks(changedSince: changedSince, chunkSize: 1) {
                chunks.withValue { $0 += 1 }
            }
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }

        #expect(chunks.get() == 1)
        #expect(session.requests.count == 2)
    }
}
