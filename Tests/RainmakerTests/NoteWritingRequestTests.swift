// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/createNote(title:category:content:modification:isFavorite:)``, ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``, ``Server/deleteNote(_:)`` and ``Server/updateNotesSettings(notesPath:fileSuffix:noteMode:showsHiddenFiles:loadsRecentNoteOnStartUp:)`` build their requests, and how the statuses the notes app answers them with map onto ``RainmakerError``.
///
/// These tests deliberately do not use the fixture tree: ``URLTestSession`` neither looks at request bodies nor at request headers, so it cannot prove which values were sent and whether `If-Match` was, and a live baseline cannot be made to produce every status the notes app may answer a change with. The recorded counterparts are in ``NoteMutationTests``. A capturing ``MockRequesting`` is used instead.
///
@Suite("Note Writing Requests") struct NoteWritingRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// A response body with a single note as the notes app sends it after creating or changing one.
    ///
    let payload = #"{"id":7,"etag":"9cf1","readonly":false,"modified":1700000000,"title":"Rainmaker","category":"Work","content":"text","favorite":true,"error":false,"errorType":"","internalPath":"/Notes/Work/Rainmaker.md","shareTypes":[],"isShared":false}"#

    ///
    /// A response body with the settings as notes app 6.1.0 sends them after changing them.
    ///
    let settingsPayload = #"{"notesPath":"Notes","fileSuffix":".txt","noteMode":"preview","showHidden":true,"loadRecentOnStartUp":false}"#

    ///
    /// The headers every supported response of the notes app carries.
    ///
    let supportedHeaders = ["X-Notes-API-Versions": "0.2, 1.3, 1.4"]

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: any Requesting, user: String? = "admin", password: String? = "admin") -> Server {
        Server(address: serverAddress, password: password, user: user, session: session, userAgent: "RainmakerTests")
    }

    ///
    /// Read the JSON object a captured request carries as its body.
    ///
    private func jsonBody(of request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    ///
    /// Read the path of a captured request.
    ///
    private func path(of request: URLRequest) throws -> String {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return components.path
    }

    // MARK: - Creating

    @Test("Creating Posts Every Value As JSON")
    func createPostsJSON() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)

        // The fraction of a second is dropped rather than rounded, because the server stores whole seconds.
        let note = try await makeServer(session: session).createNote(title: "Rainmaker", category: "Work", content: "text", modification: Date(timeIntervalSince1970: 1_700_000_000.9), isFavorite: true)

        let request = try #require(session.requests.first)
        let body = try jsonBody(of: request)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1/notes")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        #expect(request.value(forHTTPHeaderField: "If-Match") == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        // The keys are the server's names rather than those of the model, and the moment is sent as whole seconds since the Unix epoch.
        #expect(Set(body.keys) == ["title", "category", "content", "modified", "favorite"])
        #expect(body["title"] as? String == "Rainmaker")
        #expect(body["category"] as? String == "Work")
        #expect(body["content"] as? String == "text")
        #expect(body["modified"] as? Int == 1_700_000_000)
        #expect(body["favorite"] as? Bool == true)

        // The result is the note as the server stored it, which is what a caller adopts the sanitized title from.
        #expect(note.id == 7)
        #expect(note.entityTag == "9cf1")
        #expect(note.title == "Rainmaker")
        #expect(note.path == "/Notes/Work/Rainmaker.md")
    }

    @Test("Creating With Defaults Leaves The Modification Out")
    func createWithDefaults() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).createNote(title: "Rainmaker")

        let body = try jsonBody(of: #require(session.requests.first))

        // Without a moment the server stamps the note with the moment it wrote it, while the other values are always sent.
        #expect(Set(body.keys) == ["title", "category", "content", "favorite"])
        #expect(body["category"] as? String == "")
        #expect(body["content"] as? String == "")
        #expect(body["favorite"] as? Bool == false)
    }

    @Test("Creating At The Epoch Leaves The Modification Out")
    func createAtEpoch() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).createNote(title: "Rainmaker", modification: Date(timeIntervalSince1970: 0))

        let body = try jsonBody(of: #require(session.requests.first))

        // The server cannot store a moment at or before the epoch, and it takes zero as no moment at all, so nothing is sent rather than a value it would ignore.
        #expect(body["modified"] == nil)
    }

    @Test("Creating Without Room Is Reported As Such")
    func createWithoutRoom() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 507, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.insufficientStorage) {
            _ = try await makeServer(session: session).createNote(title: "Rainmaker")
        }
    }

    @Test("Creating Requires A Note In Response")
    func createWithoutNote() async throws {
        let session = MockRequesting(string: "[]", headerFields: supportedHeaders)

        await #expect {
            _ = try await makeServer(session: session).createNote(title: "Rainmaker")
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("Creating Requires A Supported App")
    func createOnOutdatedApp() async throws {
        let session = MockRequesting(string: payload, headerFields: ["X-Notes-API-Versions": "0.2, 1.3"])

        await #expect(throws: RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])) {
            _ = try await makeServer(session: session).createNote(title: "Rainmaker")
        }

        // An outdated app only reveals its version in the answer to the request it already carried out, so the note was created all the same, which the documentation warns about.
        #expect(session.requests.count == 1)
        #expect(session.requests.first?.httpMethod == "POST")
    }

    @Test("Updating On An Outdated App Has Already Sent The Change")
    func updateOnOutdatedApp() async throws {
        let session = MockRequesting(string: payload, headerFields: ["X-Notes-API-Versions": "0.2, 1.3"])

        await #expect(throws: RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])) {
            _ = try await makeServer(session: session).updateNote(7, content: "text")
        }

        // The version is only learned from the answer, so the change was made by the time the error is thrown.
        #expect(session.requests.count == 1)
        #expect(session.requests.first?.httpMethod == "PUT")
    }

    @Test("Deleting On An Outdated App Has Already Sent The Deletion")
    func deleteOnOutdatedApp() async throws {
        let session = MockRequesting(string: "[]", headerFields: ["X-Notes-API-Versions": "0.2, 1.3"])

        await #expect(throws: RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])) {
            try await makeServer(session: session).deleteNote(7)
        }

        // The version is only learned from the answer, so the note was deleted by the time the error is thrown.
        #expect(session.requests.count == 1)
        #expect(session.requests.first?.httpMethod == "DELETE")
    }

    @Test("A Success Not Sent By The Notes App Is A Decoding Failure")
    func createAnsweredByProxy() async throws {
        let session = MockRequesting(string: "<!DOCTYPE html><html><body>Log in</body></html>", headerFields: [:])

        // A login page an authenticating proxy answers with lacks the notes app's version header, which must not read as an outdated app.
        await #expect {
            _ = try await makeServer(session: session).createNote(title: "Rainmaker")
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("Cancelling A Creation Cancels Its Request")
    func cancelCreation() async throws {
        let session = SuspendingRequesting(answering: 0, through: MockRequesting(string: payload, headerFields: supportedHeaders))
        let server = makeServer(session: session)

        let creation = Task {
            try await server.createNote(title: "Rainmaker")
        }

        // The request runs within the calling task, so cancelling that task ends the request in flight, which is what a Shortcuts action relies on when it is stopped.
        #expect(try await eventually { session.suspendedCount == 1 })
        creation.cancel()

        let result = await creation.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(try await eventually { session.suspendedCount == 0 })
        #expect(session.receivedCount == 1)
    }

    // MARK: - Updating

    @Test("Updating Sends Only The Given Values")
    func updateSendsGivenValues() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).updateNote(7, content: "text")

        let request = try #require(session.requests.first)
        let body = try jsonBody(of: request)

        #expect(request.httpMethod == "PUT")
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1/notes/7")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        // Everything not given is left out rather than sent as null, so the server keeps it as it is, and without an entity tag the change is unconditional.
        #expect(Set(body.keys) == ["content"])
        #expect(body["content"] as? String == "text")
        #expect(request.value(forHTTPHeaderField: "If-Match") == nil)
    }

    @Test("Updating Sends Every Given Value")
    func updateSendsEveryValue() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).updateNote(7, title: "Rainmaker", category: "", content: "text", modification: Date(timeIntervalSince1970: 1_700_000_000), isFavorite: false)

        let body = try jsonBody(of: #require(session.requests.first))

        // An empty category is a value of its own, which moves the note out of every category, and false is sent as well rather than taken for absent.
        #expect(Set(body.keys) == ["title", "category", "content", "modified", "favorite"])
        #expect(body["title"] as? String == "Rainmaker")
        #expect(body["category"] as? String == "")
        #expect(body["modified"] as? Int == 1_700_000_000)
        #expect(body["favorite"] as? Bool == false)
    }

    @Test("Updating Only The Favorite Sends Nothing Else")
    func updateFavoriteOnly() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        let note = try await makeServer(session: session).updateNote(7, isFavorite: true)

        let body = try jsonBody(of: #require(session.requests.first))

        #expect(Set(body.keys) == ["favorite"])
        #expect(note.isFavorite)
    }

    @Test("Updating Sends The Entity Tag Quoted In If-Match", arguments: ["9cf1", #""9cf1""#, #"W/"9cf1""#])
    func updateSendsIfMatch(_ entityTag: String) async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).updateNote(7, content: "text", ifMatching: entityTag)

        let request = try #require(session.requests.first)

        // The server compares the header against the quoted tag it computed, so every form of the tag is sent the same way.
        #expect(request.value(forHTTPHeaderField: "If-Match") == #""9cf1""#)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("A Conflict Carries The Current Note")
    func conflictCarriesCurrentNote() async throws {
        let session = MockRequesting(string: payload, statusCode: 412, headerFields: supportedHeaders)
        let current = try JSONDecoder().decode(Note.self, from: Data(payload.utf8))

        // The notes app sends the note as it is now along with the status, which is what a caller reapplies its change to.
        await #expect(throws: RainmakerError.noteConflict(current: current)) {
            _ = try await makeServer(session: session).updateNote(7, content: "changed", ifMatching: "stale")
        }
    }

    @Test("A Conflict Without A Note Is An Unexpected Status")
    func conflictWithoutNote() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 412, headerFields: supportedHeaders)

        // Without the current note there is nothing to resolve the conflict with, so the bare status is reported.
        await #expect(throws: RainmakerError.unexpectedStatus(code: 412)) {
            _ = try await makeServer(session: session).updateNote(7, content: "changed", ifMatching: "stale")
        }
    }

    @Test("A Conflict Not Sent By The Notes App Is An Unexpected Status")
    func conflictFromElsewhere() async throws {
        let session = MockRequesting(string: payload, statusCode: 412, headerFields: [:])

        // Only the notes app's own answer carries the meaning of a conflict, whatever the body looks like.
        await #expect(throws: RainmakerError.unexpectedStatus(code: 412)) {
            _ = try await makeServer(session: session).updateNote(7, content: "changed", ifMatching: "stale")
        }
    }

    @Test("Updating A Read-Only Note Is Refused")
    func updateReadOnly() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 403, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.readOnly) {
            _ = try await makeServer(session: session).updateNote(7, content: "changed")
        }
    }

    @Test("Updating A Locked Note Is Reported As Such")
    func updateLocked() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 423, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.locked) {
            _ = try await makeServer(session: session).updateNote(7, content: "changed")
        }
    }

    @Test("Updating A Missing Note Is Not Found")
    func updateMissing() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 404, headerFields: supportedHeaders)

        // The server looks the note up before it compares the tag, so a deleted note is never reported as a conflict.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).updateNote(7, content: "changed", ifMatching: "9cf1")
        }
    }

    // MARK: - Deleting

    @Test("Deleting Targets The Note")
    func deleteTargetsNote() async throws {
        let session = MockRequesting(string: "[]", headerFields: supportedHeaders)
        try await makeServer(session: session).deleteNote(7)

        let request = try #require(session.requests.first)

        // A deletion carries neither a body nor a condition, because the server checks none.
        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "DELETE")
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1/notes/7")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "If-Match") == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("Deleting A Missing Note Is Not Found")
    func deleteMissing() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 404, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.notFound) {
            try await makeServer(session: session).deleteNote(7)
        }
    }

    @Test("Deleting Without The App Is Not Mistaken For A Missing Note")
    func deleteWithoutApp() async throws {
        let session = MockRequesting(string: "<!DOCTYPE html><html><body>Not found</body></html>", statusCode: 404, headerFields: [:])

        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            try await makeServer(session: session).deleteNote(7)
        }
    }

    @Test("Deleting A Read-Only Note Is Refused")
    func deleteReadOnly() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 403, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.readOnly) {
            try await makeServer(session: session).deleteNote(7)
        }
    }

    // MARK: - Settings

    @Test("Changing Settings Puts Only The Given Values")
    func updateSettingsSendsGivenValues() async throws {
        let session = MockRequesting(string: settingsPayload, headerFields: supportedHeaders)
        let settings = try await makeServer(session: session).updateNotesSettings(fileSuffix: ".txt")

        let request = try #require(session.requests.first)
        let body = try jsonBody(of: request)

        // The settings are only routed below version 1 of the API, whatever newer version the app serves elsewhere.
        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "PUT")
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1/settings")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        // Everything not given is left out rather than sent as null, because the server resets a setting sent as null to its default.
        #expect(Set(body.keys) == ["fileSuffix"])
        #expect(body["fileSuffix"] as? String == ".txt")

        // The result is what the server stored, which is what a caller adopts sanitized values from.
        #expect(settings == NotesSettings(notesPath: "Notes", fileSuffix: ".txt", noteMode: .preview, showsHiddenFiles: true, loadsRecentNoteOnStartUp: false))
    }

    @Test("Changing Settings Sends The Server's Names")
    func updateSettingsSendsEveryValue() async throws {
        let session = MockRequesting(string: settingsPayload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).updateNotesSettings(notesPath: "", fileSuffix: ".txt", noteMode: .preview, showsHiddenFiles: false, loadsRecentNoteOnStartUp: false)

        let body = try jsonBody(of: #require(session.requests.first))

        // The keys are the server's names rather than those of the model, the mode is sent as its raw value, and an empty path and false are values of their own rather than taken for absent.
        #expect(Set(body.keys) == ["notesPath", "fileSuffix", "noteMode", "showHidden", "loadRecentOnStartUp"])
        #expect(body["notesPath"] as? String == "")
        #expect(body["fileSuffix"] as? String == ".txt")
        #expect(body["noteMode"] as? String == "preview")
        #expect(body["showHidden"] as? Bool == false)
        #expect(body["loadRecentOnStartUp"] as? Bool == false)
    }

    @Test("Changing No Setting Sends An Empty Object")
    func updateSettingsWithoutValues() async throws {
        let session = MockRequesting(string: settingsPayload, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).updateNotesSettings()

        let body = try jsonBody(of: #require(session.requests.first))

        // The server keeps every setting the body does not name, so an empty object changes nothing and still answers with the settings.
        #expect(body.isEmpty)
    }

    @Test("Changing Settings Without The App Is Reported As Such")
    func updateSettingsWithoutApp() async throws {
        let session = MockRequesting(string: "<!DOCTYPE html><html><body>Not found</body></html>", statusCode: 404, headerFields: [:])

        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            _ = try await makeServer(session: session).updateNotesSettings(fileSuffix: ".md")
        }
    }

    @Test("Changing Settings Requires A Supported App")
    func updateSettingsOnOutdatedApp() async throws {
        let session = MockRequesting(string: settingsPayload, headerFields: ["X-Notes-API-Versions": "0.2, 1.3"])

        await #expect(throws: RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])) {
            _ = try await makeServer(session: session).updateNotesSettings(fileSuffix: ".md")
        }

        // The version is only learned from the answer, so the settings were changed by the time the error is thrown.
        #expect(session.requests.count == 1)
        #expect(session.requests.first?.httpMethod == "PUT")
    }

    // MARK: - Credentials

    @Test("Changes Require Credentials")
    func requireCredentials() async throws {
        let session = MockRequesting(string: payload, headerFields: supportedHeaders)
        let server = makeServer(session: session, user: nil, password: nil)

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.createNote(title: "Rainmaker")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.updateNote(7, content: "changed")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.deleteNote(7)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.updateNotesSettings(fileSuffix: ".md")
        }

        // Nothing is sent without credentials.
        #expect(session.requests.isEmpty)
    }
}
