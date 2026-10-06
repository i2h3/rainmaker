// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/note(_:)`` and ``Server/note(_:ifChangedFrom:)`` build their request, how the latter asks for and reports a note which did not change, and how the statuses of a lookup map onto ``RainmakerError``.
///
/// These tests deliberately do not use the fixture tree, for the reasons ``NotesRequestTests`` and ``NoteChangesRequestTests`` give: ``URLTestSession`` ignores request headers, so it cannot prove that a conditional request was made, and a live baseline cannot be made to produce every status the notes app may answer a lookup with. The recorded counterparts are in ``NotesTests``. A capturing ``MockRequesting`` is used instead.
///
@Suite("Single Note Requests") struct SingleNoteRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// A response body with a single note as the notes app sends it for a lookup.
    ///
    let payload = #"{"id":7,"etag":"9cf1","readonly":false,"modified":1700000000,"title":"Rainmaker","category":"Work","content":"text","favorite":true,"error":false,"errorType":"","internalPath":"/Notes/Work/Rainmaker.md","shareTypes":[],"isShared":false}"#

    ///
    /// The headers of a lookup as the notes app sends them, with the version header every supported response has to carry and the note's entity tag quoted.
    ///
    let supportedHeaders = [
        "X-Notes-API-Versions": "0.2, 1.3, 1.4",
        "ETag": #""9cf1""#,
    ]

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: MockRequesting) -> Server {
        Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
    }

    // MARK: - Unconditional Lookup

    @Test("Targets The Note By Its Identifier")
    func targetsNote() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        let note = try await makeServer(session: session).note(7)

        let request = try #require(session.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        // The identifier is part of the path, the lookup carries no query, and it is never answered from a local cache.
        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(components.path == "/index.php/apps/notes/api/v1/notes/7")
        #expect(components.queryItems == nil)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        #expect(note.id == 7)
        #expect(note.entityTag == "9cf1")
        #expect(note.title == "Rainmaker")
        #expect(note.category == "Work")
        #expect(note.isFavorite)
        #expect(note.path == "/Notes/Work/Rainmaker.md")
        #expect(note.modification == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("A Missing Note Is Not Found")
    func missingNote() async throws {
        let session = MockRequesting(string: #"{"errorType":"OCA\\Notes\\Service\\NoteDoesNotExistException"}"#, statusCode: 404, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])

        // The notes app answers this for an identifier it never assigned, for a deleted note and for a file which is not a note alike, and it adds its header to the answer.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).note(7)
        }
    }

    @Test("An Unavailable App Is Not Mistaken For A Missing Note")
    func unavailableApp() async throws {
        let session = MockRequesting(string: "<!DOCTYPE html><html><body>Not found</body></html>", statusCode: 404, headerFields: [:])

        // Without the header the route itself does not exist, which a client keeping its own copy must not take as a deleted note.
        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            _ = try await makeServer(session: session).note(7)
        }

        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            _ = try await makeServer(session: session).note(7, ifChangedFrom: "9cf1")
        }
    }

    @Test("An Outdated App Is Rejected")
    func outdatedApp() async throws {
        let session = MockRequesting(string: payload, headerFields: ["X-Notes-API-Versions": "0.2, 1.3"])

        await #expect(throws: RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])) {
            _ = try await makeServer(session: session).note(7)
        }
    }

    @Test("A Success Without A Note Is A Decoding Failure")
    func malformedNote() async throws {
        let session = MockRequesting(string: "[]", headerFields: supportedHeaders)

        await #expect {
            _ = try await makeServer(session: session).note(7)
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("Not Modified Is Unexpected For An Unconditional Lookup")
    func unexpectedNotModified() async throws {
        let session = MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])

        // Only a conditional request can be answered with not modified, so anything else answering it is not what was asked for.
        await #expect(throws: RainmakerError.unexpectedStatus(code: 304)) {
            _ = try await makeServer(session: session).note(7)
        }
    }

    @Test("A Lookup Requires Credentials")
    func requiresCredentials() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        let server = Server(address: serverAddress, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.note(7)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.note(7, ifChangedFrom: "9cf1")
        }

        // Nothing is sent without credentials.
        #expect(session.requests.isEmpty)
    }

    // MARK: - Conditional Lookup

    @Test("Sends The Entity Tag Quoted", arguments: [
        "9cf1",
        #""9cf1""#,
        #"W/"9cf1""#,
    ])
    func sendsQuotedEntityTag(_ entityTag: String) async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).note(7, ifChangedFrom: entityTag)

        let request = try #require(session.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        // The server only answers with not modified when the header repeats its strong tag quoted and exactly, so every shape a caller may hold is normalized to that.
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == #""9cf1""#)
        #expect(request.httpMethod == "GET")
        #expect(components.path == "/index.php/apps/notes/api/v1/notes/7")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("A Changed Note Is Returned In Full")
    func changedNote() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        let note = try await makeServer(session: session).note(7, ifChangedFrom: "outdated")

        // A tag which no longer matches makes the server answer as it would answer an unconditional lookup.
        #expect(note?.id == 7)
        #expect(note?.entityTag == "9cf1")
    }

    @Test("Not Modified Is Reported As Nil")
    func notModified() async throws {
        // The server answers a matching tag with an empty body and still sends its version header, because the notes app adds it before the server turns the status into not modified.
        let session = MockRequesting(string: "", statusCode: 304, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])
        let note = try await makeServer(session: session).note(7, ifChangedFrom: "9cf1")

        #expect(note == nil)
        #expect(session.requests.count == 1)
    }

    @Test("Polling With The Copy's Tag Returns Nil Until The Note Changes")
    func pollingUntilChanged() async throws {
        let changed = LockedValue(false)
        let payload = payload

        // The responder plays the server: it answers not modified while the request repeats the current tag, and the note in full once the note changed.
        let session = MockRequesting { request in
            let currentTag = changed.get() ? "a1b2" : "9cf1"

            if request.value(forHTTPHeaderField: "If-None-Match") == "\"\(currentTag)\"" {
                return (Data(), 304, ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])
            }

            let body = payload.replacingOccurrences(of: "9cf1", with: currentTag)
            return (Data(body.utf8), 200, ["X-Notes-API-Versions": "0.2, 1.3, 1.4", "ETag": "\"\(currentTag)\""])
        }

        let server = makeServer(session: session)
        let copy = try await server.note(7)

        #expect(try await server.note(7, ifChangedFrom: copy.entityTag) == nil)
        #expect(try await server.note(7, ifChangedFrom: copy.entityTag) == nil)

        changed.set(true)

        let refreshed = try #require(try await server.note(7, ifChangedFrom: copy.entityTag))
        #expect(refreshed.entityTag == "a1b2")
        #expect(try await server.note(7, ifChangedFrom: refreshed.entityTag) == nil)
    }

    @Test("A Missing Note Is Not Found Whatever The Tag")
    func conditionalMissingNote() async throws {
        let session = MockRequesting(string: #"{"errorType":"OCA\\Notes\\Service\\NoteDoesNotExistException"}"#, statusCode: 404, headerFields: ["X-Notes-API-Versions": "0.2, 1.3, 1.4"])

        // The server looks the note up before it compares tags, so a deleted note is never hidden behind nil.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).note(7, ifChangedFrom: "9cf1")
        }
    }
}
