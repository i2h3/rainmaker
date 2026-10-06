// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/attachment(at:ofNote:)``, ``Server/downloadAttachment(at:ofNote:to:force:)``, both variants of ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` and ``Server/deleteAttachment(at:ofNote:)`` build their requests, and how the statuses the notes app answers them with map onto ``RainmakerError``.
///
/// These tests deliberately do not use the fixture tree: ``URLTestSession`` ignores query strings, request headers and the bytes of an upload, so it cannot prove how the path of an attachment was encoded, which type a request accepts or what the multipart body of an upload looks like. The recorded counterparts are in ``NoteAttachmentTests``. A capturing ``MockRequesting`` is used instead.
///
@Suite("Note Attachment Requests") struct NoteAttachmentRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// The bytes of a tiny file to attach, which do not need to be anything in particular for a mock.
    ///
    let bytes = Data("Rainmaker".utf8)

    ///
    /// The headers every supported response of the notes app carries, which the response with the file itself lacks.
    ///
    let supportedHeaders = ["X-Notes-API-Versions": "0.2, 1.3, 1.4"]

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: any Requesting, user: String? = "admin", password: String? = "admin") -> Server {
        Server(address: serverAddress, password: password, user: user, session: session, userAgent: "RainmakerTests")
    }

    ///
    /// A location in the temporary directory which does not exist yet.
    ///
    private func makeTemporaryLocation(pathExtension: String = "png") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NoteAttachmentRequestTests-\(UUID().uuidString).\(pathExtension)")
    }

    ///
    /// Read the path of a captured request.
    ///
    private func path(of request: URLRequest) throws -> String {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return components.path
    }

    ///
    /// Read the decoded value of the `path` parameter of a captured request.
    ///
    private func pathParameter(of request: URLRequest) throws -> String? {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return components.queryItems?.first { $0.name == "path" }?.value
    }

    // MARK: - Retrieving

    @Test("Retrieving Asks For Any Type Below Version 1.4")
    func retrieve() async throws {
        let session = MockRequesting(body: bytes, headerFields: ["Content-Type": "image/png"])
        let attachment = try await makeServer(session: session).attachment(at: ".attachments.7/Rainmaker.png", ofNote: 7)

        let request = try #require(session.requests.first)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "GET")

        // Older releases of the notes app only route attachments below the version 1.4 segment.
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1.4/attachment/7")
        #expect(try pathParameter(of: request) == ".attachments.7/Rainmaker.png")
        #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        // The response carries no version header, which is accepted here unlike for every other notes feature.
        #expect(attachment == NoteAttachment(data: bytes, contentType: "image/png"))
    }

    @Test("Retrieving Encodes Reserved Characters Of The Path")
    func retrieveEncodesPath() async throws {
        let session = MockRequesting(body: bytes, headerFields: ["Content-Type": "image/png"])
        let path = "../Ä b+c&d=e#f?.png"
        _ = try await makeServer(session: session).attachment(at: path, ofNote: 7)

        let request = try #require(session.requests.first)
        let query = try #require(request.url?.query)

        // Every character the server would read as something else is encoded, `+` in particular, which PHP would otherwise decode as a space.
        #expect(query == "path=../%C3%84%20b%2Bc%26d%3De%23f?.png")
        #expect(try pathParameter(of: request) == path)
    }

    @Test("Retrieving Without A Type Assumes Bytes")
    func retrieveWithoutType() async throws {
        let session = MockRequesting(body: bytes)
        let attachment = try await makeServer(session: session).attachment(at: "Rainmaker.png", ofNote: 7)

        #expect(attachment.contentType == "application/octet-stream")
    }

    @Test("Retrieving Anything Missing Is Not Found")
    func retrieveMissing() async throws {
        // The notes app answers every failure with a bare not found status, and so does a server without the app.
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 404, headerFields: ["Content-Type": "application/json"])

        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).attachment(at: "Missing.png", ofNote: 7)
        }
    }

    @Test("Retrieving From An Outdated App Is Reported As Such")
    func retrieveFromOutdatedApp() async throws {
        // A release without the version 1.4 routes sends the request to its catch-all, which answers with an error and its version header.
        let session = MockRequesting(string: "[]", statusCode: 400, headerFields: ["X-Notes-API-Versions": "0.2, 1.3"])

        await #expect(throws: RainmakerError.unsupportedAPIVersion(app: "notes", required: "1.4", advertised: ["0.2", "1.3"])) {
            _ = try await makeServer(session: session).attachment(at: "Rainmaker.png", ofNote: 7)
        }
    }

    @Test("Retrieving With Another Failure Reports Its Status")
    func retrieveWithOtherFailure() async throws {
        let session = MockRequesting(string: "", statusCode: 500, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.unexpectedStatus(code: 500)) {
            _ = try await makeServer(session: session).attachment(at: "Rainmaker.png", ofNote: 7)
        }
    }

    @Test("Cancelling A Retrieval Cancels Its Request")
    func cancelRetrieval() async throws {
        let session = SuspendingRequesting(answering: 0, through: MockRequesting(body: bytes))
        let server = makeServer(session: session)

        let retrieval = Task {
            try await server.attachment(at: "Rainmaker.png", ofNote: 7)
        }

        // The request runs within the calling task, which is what a Shortcuts action relies on when it is stopped.
        #expect(try await eventually { session.suspendedCount == 1 })
        retrieval.cancel()

        let result = await retrieval.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(try await eventually { session.suspendedCount == 0 })
    }

    // MARK: - Downloading

    @Test("Downloading Writes The File To The Destination")
    func download() async throws {
        let session = MockRequesting(body: bytes, headerFields: ["Content-Type": "image/png"])
        let destination = makeTemporaryLocation()

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        let file = try await makeServer(session: session).downloadAttachment(at: "Rainmaker.png", ofNote: 7, to: destination)
        let request = try #require(session.requests.first)

        #expect(file == NoteAttachmentFile(location: destination, contentType: "image/png"))
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1.4/attachment/7")
        #expect(try pathParameter(of: request) == "Rainmaker.png")
        #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("Downloading Onto An Existing File Sends Nothing")
    func downloadOntoExistingFile() async throws {
        let session = MockRequesting(body: bytes, headerFields: ["Content-Type": "image/png"])
        let destination = makeTemporaryLocation()
        try Data("existing".utf8).write(to: destination)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        await #expect(throws: RainmakerError.fileAlreadyExists(destination)) {
            _ = try await makeServer(session: session).downloadAttachment(at: "Rainmaker.png", ofNote: 7, to: destination)
        }

        // The check happens before the request, so a call which cannot succeed transfers nothing and leaves the file alone.
        #expect(session.requests.isEmpty)
        #expect(try Data(contentsOf: destination) == Data("existing".utf8))
    }

    @Test("Downloading With Force Replaces An Existing File")
    func downloadWithForce() async throws {
        let session = MockRequesting(body: bytes, headerFields: ["Content-Type": "image/png"])
        let destination = makeTemporaryLocation()
        try Data("existing".utf8).write(to: destination)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        _ = try await makeServer(session: session).downloadAttachment(at: "Rainmaker.png", ofNote: 7, to: destination, force: true)

        #expect(try Data(contentsOf: destination) == bytes)
    }

    @Test("Downloading Something Missing Leaves The Destination Alone")
    func downloadMissing() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 404)
        let destination = makeTemporaryLocation()

        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).downloadAttachment(at: "Missing.png", ofNote: 7, to: destination)
        }

        // The body of the error response is never put in place of the file.
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
    }

    // MARK: - Adding

    @Test("Adding A File Posts It As A Form Below Version 1.4")
    func addFile() async throws {
        let session = MockRequesting(string: #"{"filename":".attachments.7/Rainmaker.png"}"#, headerFields: supportedHeaders)
        let source = makeTemporaryLocation()
        try bytes.write(to: source)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        let storedPath = try await makeServer(session: session).addAttachment(source, toNote: 7, fileName: "Rainmaker.png")
        let request = try #require(session.requests.first)
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))

        #expect(storedPath == ".attachments.7/Rainmaker.png")
        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1.4/attachment/7")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        // The boundary the header announces is the one which delimits the single part of the body, which carries the bytes unchanged.
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let expectedBody = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"Rainmaker.png\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8) + bytes + Data("\r\n--\(boundary)--\r\n".utf8)

        #expect(request.httpBody == expectedBody)

        // The staged body is removed once it has been sent, while the source is left alone.
        let staged = try #require(session.uploadSources.first)
        #expect(staged != source)
        #expect(staged.lastPathComponent.hasSuffix(".multipart"))
        #expect(FileManager.default.fileExists(atPath: staged.path) == false)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Adding A File Names It After The Source By Default")
    func addFileWithDefaultName() async throws {
        let session = MockRequesting(string: #"{"filename":"0123456789abcdef0123456789abcdef.png"}"#, headerFields: supportedHeaders)
        let source = makeTemporaryLocation()
        try bytes.write(to: source)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        let storedPath = try await makeServer(session: session).addAttachment(source, toNote: 7)
        let body = try #require(session.requests.first?.httpBody)

        // Older releases of the notes app store the file under a random name and return it as it is.
        #expect(storedPath == "0123456789abcdef0123456789abcdef.png")
        #expect(body.range(of: Data("filename=\"\(source.lastPathComponent)\"".utf8)) != nil)
    }

    @Test("Adding Bytes Posts Them Under The Given Name")
    func addData() async throws {
        let session = MockRequesting(string: #"{"filename":".attachments.7/Rainmaker.png"}"#, headerFields: supportedHeaders)
        let storedPath = try await makeServer(session: session).addAttachment(bytes, toNote: 7, fileName: "Rainmaker.png")
        let request = try #require(session.requests.first)
        let body = try #require(request.httpBody)

        #expect(storedPath == ".attachments.7/Rainmaker.png")
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1.4/attachment/7")
        #expect(body.range(of: Data("name=\"file\"; filename=\"Rainmaker.png\"\r\n".utf8)) != nil)
        #expect(body.range(of: Data("\r\n\r\n".utf8) + bytes + Data("\r\n--".utf8)) != nil)

        let staged = try #require(session.uploadSources.first)
        #expect(FileManager.default.fileExists(atPath: staged.path) == false)
    }

    @Test("Adding Escapes The File Name")
    func addEscapesFileName() async throws {
        let session = MockRequesting(string: #"{"filename":"x"}"#, headerFields: supportedHeaders)
        _ = try await makeServer(session: session).addAttachment(bytes, toNote: 7, fileName: "Ä \"quoted\"\r\nname.png")
        let body = try #require(session.requests.first?.httpBody)

        // A quote would end the parameter and a line break the header, while everything else is sent as UTF-8.
        #expect(body.range(of: Data("filename=\"Ä %22quoted%22name.png\"\r\n".utf8)) != nil)
    }

    @Test("Adding Writes The File Through A Small Buffer")
    func addStreamsThroughBuffer() throws {
        let source = makeTemporaryLocation()
        let destination = makeTemporaryLocation(pathExtension: "multipart")
        let contents = Data((0 ..< 10000).map { UInt8($0 % 251) })
        try contents.write(to: source)

        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        // A buffer much smaller than the file proves that the copy loops rather than stopping after the first read.
        let form = MultipartFormData(boundary: "B")
        try form.writeFile(from: source, fieldName: "file", fileName: "a.bin", to: destination, bufferSize: 7)

        let expected = Data("--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8) + contents + Data("\r\n--B--\r\n".utf8)

        #expect(try Data(contentsOf: destination) == expected)
        #expect(form.contentType == "multipart/form-data; boundary=B")
    }

    @Test("Adding A Missing File Sends Nothing")
    func addMissingFile() async throws {
        let session = MockRequesting(string: #"{"filename":"x"}"#, headerFields: supportedHeaders)

        await #expect(throws: (any Error).self) {
            _ = try await makeServer(session: session).addAttachment(makeTemporaryLocation(), toNote: 7)
        }

        #expect(session.requests.isEmpty)
    }

    @Test("Adding To A Missing Note Is Not Found")
    func addToMissingNote() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 404, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: session).addAttachment(bytes, toNote: 7, fileName: "Rainmaker.png")
        }
    }

    @Test("Adding Under A Refused Name Reports Its Status")
    func addUnderRefusedName() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 400, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.unexpectedStatus(code: 400)) {
            _ = try await makeServer(session: session).addAttachment(bytes, toNote: 7, fileName: ".htaccess")
        }
    }

    @Test("Adding Requires A Path In Response")
    func addWithoutPath() async throws {
        let session = MockRequesting(string: "[]", headerFields: supportedHeaders)

        await #expect {
            _ = try await makeServer(session: session).addAttachment(bytes, toNote: 7, fileName: "Rainmaker.png")
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("Cancelling An Addition Cancels Its Upload And Removes The Staged Body")
    func cancelAddition() async throws {
        let session = SuspendingRequesting(answering: 0, through: MockRequesting(string: #"{"filename":"x"}"#, headerFields: supportedHeaders))
        let server = makeServer(session: session)
        let bytes = bytes

        let addition = Task {
            try await server.addAttachment(bytes, toNote: 7, fileName: "Rainmaker.png")
        }

        #expect(try await eventually { session.suspendedCount == 1 })

        // The body is staged while the upload is in flight.
        let staged = try #require(session.uploadSources.first)
        #expect(FileManager.default.fileExists(atPath: staged.path))

        addition.cancel()

        let result = await addition.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(FileManager.default.fileExists(atPath: staged.path) == false)
    }

    // MARK: - Deleting

    @Test("Deleting Sends The Path Below Version 1.4")
    func delete() async throws {
        let session = MockRequesting(string: "[]", headerFields: supportedHeaders)
        try await makeServer(session: session).deleteAttachment(at: ".attachments.7/a+b.png", ofNote: 7)

        let request = try #require(session.requests.first)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "DELETE")
        #expect(try path(of: request) == "/index.php/apps/notes/api/v1.4/attachment/7")
        #expect(request.url?.query == "path=.attachments.7/a%2Bb.png")
        #expect(try pathParameter(of: request) == ".attachments.7/a+b.png")
    }

    @Test("Deleting On An Older App Is Not Allowed")
    func deleteOnOlderApp() async throws {
        // Releases before 6.1.0 route no deletion of attachments, so the server refuses the method before the app is involved.
        let session = MockRequesting(string: "", statusCode: 405)

        await #expect(throws: RainmakerError.methodNotAllowed) {
            try await makeServer(session: session).deleteAttachment(at: "Rainmaker.png", ofNote: 7)
        }
    }

    @Test("Deleting Something Missing Is Not Found")
    func deleteMissing() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 404, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.notFound) {
            try await makeServer(session: session).deleteAttachment(at: "Missing.png", ofNote: 7)
        }
    }

    @Test("Deleting From A Read-Only Note Is Refused")
    func deleteFromReadOnlyNote() async throws {
        let session = MockRequesting(string: #"{"errorType":"Exception"}"#, statusCode: 403, headerFields: supportedHeaders)

        await #expect(throws: RainmakerError.readOnly) {
            try await makeServer(session: session).deleteAttachment(at: "Rainmaker.png", ofNote: 7)
        }
    }

    @Test("Deleting Without The App Is Reported As Such")
    func deleteWithoutApp() async throws {
        let session = MockRequesting(string: "", statusCode: 404)

        await #expect(throws: RainmakerError.appUnavailable(app: "notes")) {
            try await makeServer(session: session).deleteAttachment(at: "Rainmaker.png", ofNote: 7)
        }
    }

    // MARK: - Credentials

    @Test("Require Credentials")
    func requireCredentials() async throws {
        let session = MockRequesting(body: bytes)
        let server = makeServer(session: session, user: nil, password: nil)
        let destination = makeTemporaryLocation()

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.attachment(at: "Rainmaker.png", ofNote: 7)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.downloadAttachment(at: "Rainmaker.png", ofNote: 7, to: destination)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.addAttachment(destination, toNote: 7)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.addAttachment(bytes, toNote: 7, fileName: "Rainmaker.png")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.deleteAttachment(at: "Rainmaker.png", ofNote: 7)
        }

        // Nothing is sent without credentials.
        #expect(session.requests.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
    }
}
