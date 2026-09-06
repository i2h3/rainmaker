// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/notes()`` and ``Server/notes(changedSince:)`` build their request, how they enforce the minimum notes API version, and how they decode the two shapes the server answers with.
///
/// These tests deliberately do not use the fixture tree: ``FixtureLocator`` keys fixtures by HTTP method and URL path only, so a replayed test still finds its fixture when the query string is wrong or missing entirely and therefore cannot prove anything about it. A capturing ``MockRequesting`` is used instead, which also makes it possible to serve responses a live baseline cannot be made to produce, such as those of a server without the notes app, one running an app too old to be supported, or one answering a success with something other than notes.
///
@Suite("Note Requests") struct NotesRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// The response of an account without a single note, enough for a call to succeed so the captured request can be inspected.
    ///
    let emptyList = "[]"

    ///
    /// The headers of a notes app new enough to be supported, mirroring what a live server sends.
    ///
    /// Every response has to carry this, because the minimum API version is enforced before the payload is even looked at.
    ///
    let supportedHeaders = ["X-Notes-API-Versions": "0.2, 1.3, 1.4"]

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: MockRequesting) -> Server {
        Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
    }

    ///
    /// Build a server answering every request with the given body, status and headers, defaulting to a supported app.
    ///
    private func makeServer(body: String, statusCode: Int = 200, headerFields: [String: String]? = nil) -> Server {
        makeServer(session: MockRequesting(string: body, statusCode: statusCode, headerFields: headerFields ?? supportedHeaders))
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

    @Test("Full Retrieval Carries No Query")
    func fullRetrieval() async throws {
        let session = MockRequesting(string: emptyList, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).notes()

        let (path, query) = try captured(from: session)

        #expect(path == "/index.php/apps/notes/api/v1/notes")

        // Not asking for a chunk size is what makes the server answer with the whole collection at once, so no query parameter is sent at all.
        #expect(query.isEmpty)
    }

    @Test("Changed Since Reaches The Query")
    func changedSince() async throws {
        let session = MockRequesting(string: emptyList, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).notes(changedSince: Date(timeIntervalSince1970: 1_700_000_000))

        let (path, query) = try captured(from: session)

        #expect(path == "/index.php/apps/notes/api/v1/notes")
        #expect(query["pruneBefore"] == "1700000000")
    }

    @Test("Changed Since The Epoch Prunes Nothing")
    func changedSinceEpoch() async throws {
        let session = MockRequesting(string: emptyList, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).notes(changedSince: Date(timeIntervalSince1970: 0))

        let (_, query) = try captured(from: session)

        // A moment at or before the Unix epoch has no positive number of seconds to express it, and the server treats a zero as no pruning at all.
        #expect(query["pruneBefore"] == "0")
    }

    @Test("Request Is Authenticated And Not An OCS Request")
    func requestHeaders() async throws {
        let session = MockRequesting(string: emptyList, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).notes()

        let request = try #require(session.requests.first)
        let headers = request.allHTTPHeaderFields

        #expect(request.httpMethod == "GET")
        #expect(headers?["Accept"] == "application/json")
        #expect(headers?["User-Agent"] == "RainmakerTests")
        #expect(headers?["Authorization"] == "Basic \(Data("admin:admin".utf8).base64EncodedString())")

        // The notes API is not reachable through OCS, so the header announcing an OCS request must not be sent.
        #expect(headers?["OCS-APIRequest"] == nil)
    }

    @Test("Settings Lookup Targets The Settings Endpoint")
    func settingsRequest() async throws {
        let session = MockRequesting(string: #"{"notesPath":"Notes","fileSuffix":".md"}"#, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).notesSettings()

        let (path, query) = try captured(from: session)

        #expect(path == "/index.php/apps/notes/api/v1/settings")
        #expect(query.isEmpty)
    }

    @Test("Settings Decode And Ignore What Is Not Modelled")
    func settingsDecoding() async throws {
        // The `noteMode` field is what a live server sends beyond what the API documents, so it has to be ignored rather than break the lookup.
        let payload = #"{"notesPath":"Notizen","fileSuffix":".md","noteMode":"rich"}"#
        let settings = try await makeServer(body: payload).notesSettings()

        #expect(settings.notesPath == "Notizen")
        #expect(settings.fileSuffix == ".md")
    }

    // MARK: - Availability And Version

    @Test("Unavailable App Is Not Found")
    func unavailableApp() async throws {
        let server = makeServer(body: "<!DOCTYPE html><html><body>Not found</body></html>", statusCode: 404)

        // Without the notes app installed and enabled the route does not exist at all.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.notes()
        }
    }

    @Test("App Older Than The Minimum API Version Is Rejected")
    func outdatedApp() async throws {
        let server = makeServer(body: emptyList, headerFields: ["X-Notes-API-Versions": "0.2, 1.2"])
        let expected = RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.3", advertised: ["0.2", "1.2"])

        // An app which answers but predates the required API version is reported as such rather than as a missing app, because updating it is what a client should tell the user to do.
        await #expect(throws: expected) {
            _ = try await server.notes()
        }
    }

    @Test("Missing Version Header Is Rejected")
    func missingVersionHeader() async throws {
        let server = makeServer(body: emptyList, headerFields: [:])
        let expected = RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.3", advertised: [])

        // Every response of a supported app advertises its API versions, so their absence means the app cannot be relied upon.
        await #expect(throws: expected) {
            _ = try await server.notes()
        }
    }

    @Test("The Minimum API Version Is Accepted")
    func minimumVersion() async throws {
        let server = makeServer(body: emptyList, headerFields: ["X-Notes-API-Versions": "0.2, 1.3"])

        // The requirement is a floor, so an app serving exactly it has to work.
        await #expect(throws: Never.self) {
            _ = try await server.notes()
        }
    }

    @Test("A Newer Major API Version Alone Does Not Satisfy The Requirement")
    func newerMajorVersion() async throws {
        let server = makeServer(body: emptyList, headerFields: ["X-Notes-API-Versions": "2.0"])
        let expected = RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.3", advertised: ["2.0"])

        // A future major version is a different API with its own base path, so it must not silently pass a check meant for this one.
        await #expect(throws: expected) {
            _ = try await server.notes()
        }
    }

    @Test("The Requirement Is Enforced On The Settings Lookup Too")
    func outdatedAppOnSettings() async throws {
        let server = makeServer(body: #"{"notesPath":"Notes","fileSuffix":".md"}"#, headerFields: ["X-Notes-API-Versions": "0.2"])
        let expected = RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.3", advertised: ["0.2"])

        await #expect(throws: expected) {
            _ = try await server.notesSettings()
        }
    }

    @Test("The Requirement Is Enforced On Incremental Retrieval Too")
    func outdatedAppOnIncrementalRetrieval() async throws {
        let server = makeServer(body: emptyList, headerFields: ["X-Notes-API-Versions": "0.2"])
        let expected = RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.3", advertised: ["0.2"])

        await #expect(throws: expected) {
            _ = try await server.notes(changedSince: Date(timeIntervalSince1970: 1_600_000_000))
        }
    }

    @Test("The Capability Reports The Same Requirement")
    func capabilityReportsSupport() throws {
        func notes(advertising apiVersions: String) throws -> Notes {
            try JSONDecoder().decode(Notes.self, from: Data(#"{"api_version":[\#(apiVersions)],"version":"6.0.1","notes_path":"Notes"}"#.utf8))
        }

        #expect(try notes(advertising: #""0.2","1.3","1.4""#).isSupported)
        #expect(try notes(advertising: #""0.2","1.3""#).isSupported)
        #expect(try notes(advertising: #""1.4""#).isSupported)
        #expect(try notes(advertising: #""0.2","1.2""#).isSupported == false)
        #expect(try notes(advertising: #""2.0""#).isSupported == false)
        #expect(try notes(advertising: "").isSupported == false)

        // A version scheme this library does not know about must not make an otherwise supported server look unsupported.
        #expect(try notes(advertising: #""nonsense","1.3""#).isSupported)

        // A patch component the server does not send today would still have to read as supported.
        #expect(try notes(advertising: #""1.3.1""#).isSupported)
        #expect(try notes(advertising: #""1.2.9""#).isSupported == false)

        #expect(Notes.minimumAPIVersion == "1.3")
    }

    // MARK: - Decoding

    @Test("Malformed Success Response Is A Decoding Failure")
    func malformedResponse() async throws {
        let server = makeServer(body: "<!DOCTYPE html><html><body>Log in</body></html>")

        // This endpoint carries no OCS envelope whose status could vouch for the payload, so a success response with something else entirely, such as a login page served by a proxy, has to surface as a library error rather than as an opaque Foundation one.
        await #expect {
            _ = try await server.notes()
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("A Note Without The Required Fields Is A Decoding Failure")
    func noteWithoutRequiredFields() async throws {
        let payload = #"[{"id":76,"modified":1376753464,"title":"New note","category":"sub-directory","content":"New note","favorite":false}]"#
        let server = makeServer(body: payload)

        // This is the shape an app older than API version 1.2 sends, without an entity tag and without the read-only flag. Such an app is refused by the version check, so a payload like this from an app claiming to be supported is a response this library cannot describe.
        await #expect {
            _ = try await server.notes()
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("Ignores The Fields Which Are Not Modelled")
    func ignoresUnmodelledFields() async throws {
        let payload = ##"[{"id":86,"title":"Rainmaker","modified":1700000000,"category":"","favorite":false,"readonly":false,"internalPath":"/Notes/Rainmaker.md","shareTypes":[],"isShared":false,"error":false,"errorType":"","content":"# Rainmaker\n","etag":"c649e503de046daca1b998c2e52b2a94"}]"##
        let server = makeServer(body: payload)
        let note = try #require(try await server.notes().first)

        // This is verbatim what a live server sends, which is more than the API documents. Unknown fields must be ignored rather than break the retrieval, which is what the API's compatibility rules ask of a client.
        #expect(note.id == 86)
        #expect(note.title == "Rainmaker")
        #expect(note.entityTag == "c649e503de046daca1b998c2e52b2a94")
        #expect(note.isReadOnly == false)
        #expect(note.modification == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Partitions The Pruned Entries")
    func partitionsPrunedEntries() async throws {
        let payload = #"[{"id":1,"etag":"a","readonly":false,"modified":1700000000,"title":"Changed","category":"","content":"body","favorite":false},{"id":2},{"id":3}]"#
        let server = makeServer(body: payload)
        let changes = try await server.notes(changedSince: Date(timeIntervalSince1970: 1_600_000_000))

        // A response to a pruning request mixes both shapes, and telling them apart is what the caller depends on to know which notes it already has.
        #expect(changes.changed.count == 1)
        #expect(changes.changed.first?.title == "Changed")
        #expect(changes.unchanged == [2, 3])
    }

    @Test("A Malformed Note Is Not Mistaken For A Pruned One")
    func malformedNoteIsNotPruned() async throws {
        let payload = #"[{"id":1,"title":"Missing everything else"}]"#
        let server = makeServer(body: payload)

        // An entry carrying a title is a note the server sent in full, so one which is missing the rest is a response this library cannot describe rather than a note reported as unchanged.
        await #expect {
            _ = try await server.notes(changedSince: Date(timeIntervalSince1970: 1_600_000_000))
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }
}
