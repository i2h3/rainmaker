// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/searchUsers(_:)``, ``Server/createConversation(with:)``, ``Server/sendMessage(_:toConversation:)`` and ``Server/sendFile(_:toConversation:caption:)`` build their requests and how the statuses the server and the Talk app answer them with map onto ``RainmakerError``.
///
/// These tests deliberately do not use the fixture tree: ``URLTestSession`` ignores query strings, request headers and request bodies, so it cannot prove what a search asked for, what a conversation was created with or what a message carried, and a live container cannot be made to answer with a read-only conversation, an exhausted quota or a failure after an upload. A capturing ``MockRequesting`` is used instead, whose ``MockRequesting/Responder`` answers the several requests of sending a file each in its own way.
///
@Suite("Conversation Writing Requests") struct ConversationWritingRequestTests {
    ///
    /// The address of the server the tests send to.
    ///
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// The token of the conversation the tests send to.
    ///
    let token = "abcd1234"

    ///
    /// The draft folder the Talk app names for the conversation, relative to the account's files and with a space in the name of the conversation, so that its encoding is covered as well.
    ///
    let folder = "Talk/Weekly Sync-abcd1234/Draft"

    ///
    /// The moment the files the tests send were last modified, pinned because the name of the uploaded draft is derived from it.
    ///
    let modification = Date(timeIntervalSince1970: 1_700_000_000)

    ///
    /// The bytes of the files the tests send, which do not need to be anything in particular for a mock.
    ///
    let bytes = Data("%PDF-1.7 Rainmaker".utf8)

    ///
    /// The response of the server to a search, shaped as its autocompletion shapes every match, with a user status set for one match and none for the other.
    ///
    let searchResults = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[{"id":"alice","label":"Alice Liddell","icon":"icon-user","source":"users","status":{"status":"online","message":null,"icon":null,"clearAt":null},"subline":"","shareWithDisplayNameUnique":"alice@example.com"},{"id":"5f2b9c1e-4a7d","label":"Alicia Keys","icon":"icon-user","source":"users","status":"","subline":"","shareWithDisplayNameUnique":"alicia@example.com"}]}}"#

    ///
    /// The response of the Talk app to the creation of a one-to-one conversation with `alice`, shaped like the rooms a live server lists.
    ///
    let conversation = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"id":7,"token":"q3x9pz2k","type":1,"name":"alice","displayName":"Alice Liddell","objectType":"","objectId":"","participantType":1,"participantFlags":0,"readOnly":0,"hasPassword":false,"hasCall":false,"callStartTime":0,"callRecording":0,"canStartCall":true,"lastActivity":1700000000,"lastReadMessage":0,"unreadMessages":0,"unreadMention":false,"unreadMentionDirect":false,"isFavorite":false,"canLeaveConversation":true,"canDeleteConversation":false,"notificationLevel":1,"notificationCalls":1,"lobbyState":0,"lobbyTimer":0,"lastPing":0,"sessionId":"0","sipEnabled":0,"actorType":"users","actorId":"admin","attendeeId":12,"permissions":254,"attendeePermissions":0,"callPermissions":0,"defaultPermissions":0,"canEnableSIP":false,"attendeePin":"","description":"","lastCommonReadMessage":0,"listable":0,"callFlag":0,"messageExpiration":0,"avatarVersion":"00000000","isCustomAvatar":false,"breakoutRoomMode":0,"breakoutRoomStatus":0,"recordingConsent":0,"mentionPermissions":0,"isArchived":false,"isImportant":false,"isSensitive":false,"tagIds":[],"attributes":0,"lastMessage":[]}}}"#

    ///
    /// The response of the Talk app to a sent message, which the library does not look at beyond its status.
    ///
    let sentMessage = #"{"ocs":{"meta":{"status":"ok","statuscode":201,"message":"OK"},"data":{"id":42,"token":"abcd1234","actorType":"users","actorId":"admin","message":"Hello","messageType":"comment"}}}"#

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
    /// Read the decoded path of a captured request.
    ///
    private func path(of request: URLRequest) throws -> String {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return components.path
    }

    ///
    /// Read the query items of a captured request, keyed by name.
    ///
    private func query(of request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        return (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }
    }

    ///
    /// Describe each captured request by its method and its decoded path, which is how the order of the requests of sending a file is compared.
    ///
    private func summary(of requests: [URLRequest]) -> [String] {
        requests.map { "\($0.httpMethod ?? "") \($0.url?.compatibilityPath(percentEncoded: false) ?? "")" }
    }

    ///
    /// Write a file of ``bytes`` with the given name into a new folder in the temporary directory and pin its modification date to ``modification``, returning both so that the test removes the folder again.
    ///
    private func makeSourceFile(named name: String) throws -> (file: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ConversationWritingRequestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

        let file = folder.appendingPathComponent(name)
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modification], ofItemAtPath: file.path)

        return (file, folder)
    }

    ///
    /// The path below the account's WebDAV root the draft of the given file is uploaded to, derived the way the library promises to derive it.
    ///
    private func draftPath(for fileName: String, pathExtension: String) -> String {
        let transferName = Server.uploadTransferName(for: "\(token)/\(fileName)", size: Int64(bytes.count), modification: modification)
        return pathExtension.isEmpty ? "\(folder)/\(transferName)" : "\(folder)/\(transferName).\(pathExtension)"
    }

    ///
    /// Build a mock answering the requests of sending a file as the server would, with the given statuses for asking for the draft folder, for uploading the draft, for posting the file and for deleting the draft, and with the draft not existing yet when it is looked up before the upload.
    ///
    private func makeSendFileSession(folderStatus: Int = 200, folderBody: String? = nil, uploadStatus: Int = 201, attachStatus: Int = 200, deleteStatus: Int = 204) -> MockRequesting {
        let folderBody = folderBody ?? #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"folder":"\#(folder)","renames":[]}}}"#
        let attachBody = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"renames":[]}}}"#

        return MockRequesting { request in
            let path = request.url?.compatibilityPath(percentEncoded: false) ?? ""

            switch request.httpMethod {
                case "POST" where path.hasSuffix("/attachment/folder"):
                    return (Data(folderBody.utf8), folderStatus, ["Content-Type": "application/json; charset=utf-8"])
                case "POST" where path.hasSuffix("/attachment"):
                    return (Data(attachBody.utf8), attachStatus, ["Content-Type": "application/json; charset=utf-8"])
                case "PROPFIND":
                    return (Data(), 404, nil)
                case "PUT":
                    return (Data(), uploadStatus, nil)
                case "DELETE":
                    return (Data(), deleteStatus, nil)
                default:
                    return (Data(), 500, nil)
            }
        }
    }

    // MARK: - Credentials

    @Test("Every Call Requires Credentials")
    func requireCredentials() async throws {
        let session = MockRequesting(string: searchResults)
        let server = makeServer(session: session, user: nil, password: nil)
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.searchUsers("ali")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.createConversation(with: "alice")
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.sendMessage("Hello", toConversation: token)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            try await server.sendFile(source.file, toConversation: token)
        }

        // Credentials are required, so every call fails before any network request is made.
        #expect(session.requests.isEmpty)
    }

    // MARK: - Searching Users

    @Test("Searching Asks The Autocompletion For A New Conversation")
    func searchRequest() async throws {
        let session = MockRequesting(string: searchResults)
        _ = try await makeServer(session: session).searchUsers("ali")

        let request = try #require(session.requests.first)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(try path(of: request) == "/ocs/v2.php/core/autocomplete/get")

        // Naming a new call as the context is what the Talk clients do when they start a conversation, so the server tailors its results to that.
        #expect(try query(of: request) == ["search": "ali", "itemType": "call", "itemId": "new"])
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("admin:admin".utf8).base64EncodedString())")
    }

    @Test("Searching Sends Reserved Characters Of The Term Intact")
    func searchEncodesTerm() async throws {
        let session = MockRequesting(string: searchResults)
        let term = "Doe+Sons & Co=1"
        _ = try await makeServer(session: session).searchUsers(term)

        let request = try #require(session.requests.first)

        // The server would read an unencoded `+` as a space and an unencoded `&` or `=` as delimiters of the query.
        #expect(request.url?.query == "search=Doe%2BSons%20%26%20Co%3D1&itemType=call&itemId=new")
        #expect(try query(of: request)["search"] == term)
    }

    @Test("Searching Decodes The Matches In Order")
    func searchDecodes() async throws {
        let users = try await makeServer(session: MockRequesting(string: searchResults)).searchUsers("ali")

        // The identifier is what every further request expects, which for an account backed by a directory differs from anything a person would type.
        #expect(users == [User(id: "alice", displayName: "Alice Liddell"), User(id: "5f2b9c1e-4a7d", displayName: "Alicia Keys")])
    }

    @Test("Searching Without Matches Returns None")
    func searchWithoutMatches() async throws {
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[]}}"#
        let users = try await makeServer(session: MockRequesting(string: body)).searchUsers("zzz")

        #expect(users.isEmpty)
    }

    @Test("Searching Reports A Failure Status", arguments: [401, 404, 500])
    func searchFailureStatus(statusCode: Int) async throws {
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":997,"message":"Current user is not logged in"},"data":[]}}"#
        let session = MockRequesting(string: body, statusCode: statusCode)

        await #expect(throws: RainmakerError.unexpectedStatus(code: statusCode)) {
            _ = try await makeServer(session: session).searchUsers("ali")
        }
    }

    @Test("Searching With Something Other Than Matches Fails To Decode")
    func searchUndecodable() async throws {
        let session = MockRequesting(string: "<!DOCTYPE html><html></html>", headerFields: ["Content-Type": "text/html"])

        await #expect {
            _ = try await makeServer(session: session).searchUsers("ali")
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    @Test("Searching With A Failed OCS Envelope Fails To Decode")
    func searchFailedEnvelope() async throws {
        // A success status carrying a failed envelope must not pass for a search without matches.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":100,"message":"Broken"},"data":[]}}"#
        let session = MockRequesting(string: body)

        await #expect(throws: RainmakerError.responseDecodingFailed(reason: "OCS request failed (100): Broken")) {
            _ = try await makeServer(session: session).searchUsers("ali")
        }
    }

    // MARK: - Creating Conversations

    @Test("Creating A Conversation Posts A One-To-One Room As JSON")
    func createRequest() async throws {
        let session = MockRequesting(string: conversation, statusCode: 201)
        _ = try await makeServer(session: session).createConversation(with: "alice")

        let request = try #require(session.requests.first)
        let body = try jsonBody(of: request)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(try path(of: request) == "/ocs/v2.php/apps/spreed/api/v4/room")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("admin:admin".utf8).base64EncodedString())")

        // A room type of 1 is a one-to-one conversation, and nothing else is sent, such as a name the server would ignore for it.
        #expect(Set(body.keys) == ["roomType", "invite"])
        #expect(body["roomType"] as? Int == 1)
        #expect(body["invite"] as? String == "alice")
    }

    @Test("Creating A Conversation Returns The New Or The Existing One", arguments: [200, 201])
    func createDecodes(statusCode: Int) async throws {
        // The server answers with `201` for a conversation it created and with `200` for the one which already existed.
        let created = try await makeServer(session: MockRequesting(string: conversation, statusCode: statusCode)).createConversation(with: "alice")

        #expect(created.id == 7)
        #expect(created.token == "q3x9pz2k")
        #expect(created.type == .oneToOne)
        #expect(created.displayName == "Alice Liddell")
        #expect(created.avatarVersion == "00000000")
        #expect(created.lastActivity == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(created.unreadMessages == 0)
        #expect(created.unreadMention == false)
    }

    @Test("Creating A Conversation With An Unknown User Is Not Found")
    func createNotFound() async throws {
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":404,"message":""},"data":[]}}"#

        await #expect(throws: RainmakerError.notFound) {
            _ = try await makeServer(session: MockRequesting(string: body, statusCode: 404)).createConversation(with: "nobody")
        }
    }

    @Test("Creating A Conversation Reports Another Failure Status", arguments: [400, 403])
    func createFailureStatus(statusCode: Int) async throws {
        // The server answers `403` for the account's own identifier, for a user the account may not see and for an account which may not use Talk, while `400` stands for any other failure status.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":400,"message":""},"data":{"error":"invite"}}}"#

        await #expect(throws: RainmakerError.unexpectedStatus(code: statusCode)) {
            _ = try await makeServer(session: MockRequesting(string: body, statusCode: statusCode)).createConversation(with: "admin")
        }
    }

    @Test("Creating A Conversation Answered With Something Else Fails To Decode", arguments: [
        "<!DOCTYPE html><html></html>",
        #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[]}}"#,
        #"{"ocs":{"meta":{"status":"failure","statuscode":100,"message":"Broken"},"data":{"id":7,"token":"q3x9pz2k","type":1,"displayName":"Alice Liddell","avatarVersion":"00000000","lastActivity":0,"unreadMessages":0,"unreadMention":false}}}"#,
    ])
    func createUndecodable(body: String) async throws {
        await #expect {
            _ = try await makeServer(session: MockRequesting(string: body)).createConversation(with: "alice")
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }
    }

    // MARK: - Sending Messages

    @Test("Sending A Message Posts It Unchanged As JSON")
    func sendMessageRequest() async throws {
        let session = MockRequesting(string: sentMessage, statusCode: 201)
        let message = "# Shared from Safari\n\n**Rainmaker** is at https://example.com/a/b?c=d&e=f+g#h\n- Ä \u{1F600}"
        try await makeServer(session: session).sendMessage(message, toConversation: token)

        let request = try #require(session.requests.first)
        let body = try jsonBody(of: request)

        #expect(session.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(try path(of: request) == "/ocs/v2.php/apps/spreed/api/v1/chat/abcd1234")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("admin:admin".utf8).base64EncodedString())")

        // The server renders the Markdown and previews the link itself, so neither is touched on the way.
        #expect(Set(body.keys) == ["message"])
        #expect(body["message"] as? String == message)
    }

    @Test("Sending A Message Maps The Statuses Of The Chat", arguments: zip([403, 404, 412, 413, 507, 200], [RainmakerError.readOnly, .notFound, .unexpectedStatus(code: 412), .unexpectedStatus(code: 413), .insufficientStorage, .unexpectedStatus(code: 200)]))
    func sendMessageFailureStatus(statusCode: Int, expected: RainmakerError) async throws {
        // A `200` is not what the chat answers a stored message with, so it is not taken for one either.
        let session = MockRequesting(string: #"{"ocs":{"meta":{"status":"failure","statuscode":0,"message":""},"data":[]}}"#, statusCode: statusCode)

        await #expect(throws: expected) {
            try await makeServer(session: session).sendMessage("Hello", toConversation: token)
        }
    }

    @Test("Cancelling The Task Cancels Sending A Message")
    func sendMessageCancellation() async throws {
        let session = SuspendingRequesting(answering: 0, through: MockRequesting(string: sentMessage, statusCode: 201))
        let server = makeServer(session: session)

        let sending = Task {
            try await server.sendMessage("Hello", toConversation: token)
        }

        // The request runs within the calling task, so a share extension which is dismissed ends the sending at once.
        #expect(try await eventually { session.suspendedCount == 1 })
        sending.cancel()

        let result = await sending.result

        #expect(throws: URLError.self) {
            try result.get()
        }

        #expect(try await eventually { session.suspendedCount == 0 })
    }

    // MARK: - Sending Files

    @Test("Sending A File Uploads A Draft And Posts It With Its Caption")
    func sendFile() async throws {
        let session = makeSendFileSession()
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        try await makeServer(session: session).sendFile(source.file, toConversation: token, caption: "Hello")

        let draftPath = draftPath(for: "Report 1.pdf", pathExtension: "pdf")
        let webDAVDraftPath = "/remote.php/dav/files/admin/\(draftPath)"
        let requests = session.requests

        #expect(summary(of: requests) == [
            "POST /ocs/v2.php/apps/spreed/api/v1/chat/abcd1234/attachment/folder",
            "PROPFIND \(webDAVDraftPath)",
            "PUT \(webDAVDraftPath)",
            "POST /ocs/v2.php/apps/spreed/api/v1/chat/abcd1234/attachment",
        ])

        // Asking for the draft folder needs no parameters, so no body is sent with it.
        let folderRequest = try #require(requests.first)
        #expect(folderRequest.httpBody == nil)
        #expect(folderRequest.value(forHTTPHeaderField: "OCS-APIRequest") == "true")

        // The draft is uploaded from the source itself, which is left in place.
        let upload = try #require(requests.dropFirst(2).first)
        #expect(upload.httpBody == bytes)
        #expect(session.uploadSources == [source.file])
        #expect(FileManager.default.fileExists(atPath: source.file.path))

        let attach = try #require(requests.last)
        let body = try jsonBody(of: attach)

        #expect(attach.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(body["filePath"] as? String == draftPath)
        #expect(body["fileName"] as? String == "Report 1.pdf")
        #expect((body["referenceId"] as? String)?.isEmpty == false)

        // The Talk app expects the metadata as a JSON document within a string.
        let talkMetaData = try #require(body["talkMetaData"] as? String)
        let metaData = try #require(try JSONSerialization.jsonObject(with: Data(talkMetaData.utf8)) as? [String: Any])

        #expect(Set(metaData.keys) == ["caption"])
        #expect(metaData["caption"] as? String == "Hello")
    }

    @Test("Sending A File Without Caption Sends No Metadata")
    func sendFileWithoutCaption() async throws {
        let session = makeSendFileSession()
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        try await makeServer(session: session).sendFile(source.file, toConversation: token)

        let body = try jsonBody(of: #require(session.requests.last))

        #expect(Set(body.keys) == ["filePath", "fileName", "referenceId"])
    }

    @Test("Sending A File Without Extension Names Its Draft Without One")
    func sendFileWithoutExtension() async throws {
        let session = makeSendFileSession()
        let source = try makeSourceFile(named: "README")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        try await makeServer(session: session).sendFile(source.file, toConversation: token)

        let draftPath = draftPath(for: "README", pathExtension: "")
        let upload = try #require(session.requests.first { $0.httpMethod == "PUT" })
        let body = try jsonBody(of: #require(session.requests.last))

        #expect(draftPath.split(separator: "/").last?.contains(".") == false)
        #expect(try path(of: upload) == "/remote.php/dav/files/admin/\(draftPath)")
        #expect(body["filePath"] as? String == draftPath)
        #expect(body["fileName"] as? String == "README")
    }

    @Test("Sending A Missing File Sends Nothing")
    func sendMissingFile() async throws {
        let session = makeSendFileSession()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("ConversationWritingRequestTests-\(UUID().uuidString).pdf")

        await #expect(throws: RainmakerError.notFound) {
            try await makeServer(session: session).sendFile(missing, toConversation: token)
        }

        #expect(session.requests.isEmpty)
    }

    @Test("Sending A Directory Sends Nothing")
    func sendDirectory() async throws {
        let session = makeSendFileSession()
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        await #expect(throws: RainmakerError.notFound) {
            try await makeServer(session: session).sendFile(source.folder, toConversation: token)
        }

        #expect(session.requests.isEmpty)
    }

    @Test("Sending A File Maps The Statuses Of The Draft Folder", arguments: zip([404, 403, 501, 507, 500], [RainmakerError.notFound, .readOnly, .unexpectedStatus(code: 501), .insufficientStorage, .unexpectedStatus(code: 500)]))
    func sendFileFolderFailure(statusCode: Int, expected: RainmakerError) async throws {
        // A `404` is also what a release older than Talk 24 answers, and a `501` what one answers whose folders per conversation are turned off.
        let session = makeSendFileSession(folderStatus: statusCode, folderBody: #"{"ocs":{"meta":{"status":"failure","statuscode":0,"message":""},"data":{"error":"Conversation subfolders are disabled"}}}"#)
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        await #expect(throws: expected) {
            try await makeServer(session: session).sendFile(source.file, toConversation: token)
        }

        // Nothing is uploaded without a draft folder to upload into.
        #expect(summary(of: session.requests) == ["POST /ocs/v2.php/apps/spreed/api/v1/chat/abcd1234/attachment/folder"])
    }

    @Test("Sending A File Reports An Exhausted Quota During The Upload As Such")
    func sendFileUploadOverQuota() async throws {
        let session = makeSendFileSession(uploadStatus: 507)
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        // The same condition surfaces as the same error whether the draft folder or the upload into it hit the quota.
        await #expect(throws: RainmakerError.insufficientStorage) {
            try await makeServer(session: session).sendFile(source.file, toConversation: token)
        }

        // Nothing is posted without an uploaded draft.
        #expect(summary(of: session.requests).last?.hasPrefix("PUT ") == true)
    }

    @Test("Sending A File Without A Draft Folder Fails To Decode")
    func sendFileWithoutFolder() async throws {
        let session = makeSendFileSession(folderBody: #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"renames":[]}}}"#)
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        await #expect {
            try await makeServer(session: session).sendFile(source.file, toConversation: token)
        } throws: { error in
            guard case RainmakerError.responseDecodingFailed = error else {
                return false
            }

            return true
        }

        #expect(session.requests.count == 1)
    }

    @Test("Sending A File Deletes Its Draft When Posting Fails", arguments: zip([403, 500], [RainmakerError.readOnly, .unexpectedStatus(code: 500)]))
    func sendFileAttachFailure(statusCode: Int, expected: RainmakerError) async throws {
        let session = makeSendFileSession(attachStatus: statusCode)
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        await #expect(throws: expected) {
            try await makeServer(session: session).sendFile(source.file, toConversation: token, caption: "Hello")
        }

        let webDAVDraftPath = "/remote.php/dav/files/admin/\(draftPath(for: "Report 1.pdf", pathExtension: "pdf"))"

        // The draft which was uploaded but not posted is removed again, after the posting failed.
        #expect(Array(summary(of: session.requests).suffix(2)) == [
            "POST /ocs/v2.php/apps/spreed/api/v1/chat/abcd1234/attachment",
            "DELETE \(webDAVDraftPath)",
        ])
    }

    @Test("Sending A File Reports The Failure Of Posting Over That Of Deleting The Draft")
    func sendFileAttachAndDeleteFailure() async throws {
        let session = makeSendFileSession(attachStatus: 403, deleteStatus: 500)
        let source = try makeSourceFile(named: "Report 1.pdf")

        defer {
            try? FileManager.default.removeItem(at: source.folder)
        }

        await #expect(throws: RainmakerError.readOnly) {
            try await makeServer(session: session).sendFile(source.file, toConversation: token)
        }

        #expect(session.requests.last?.httpMethod == "DELETE")
    }
}
