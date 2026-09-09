// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/conversations()`` and ``Server/conversationAvatar(_:darkTheme:)`` build their requests and how they decode what the server answers with.
///
/// These tests deliberately do not use the fixture tree: it is keyed by HTTP method and URL path only, so a replayed test cannot prove what a request carried beyond its path, and a live container cannot be made to produce the responses which matter most here. A capturing ``MockRequesting`` is used instead, which serves the responses of a server without the Talk app, of a conversation which does not exist, of a failed OCS envelope, of a conversation kind this library does not know, and of an image the server did not state the type of.
///
/// The happy paths against a real server are covered by ``ConversationsTests``.
///
@Suite("Conversation Requests") struct ConversationsRequestTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// The response of an account without a single conversation, enough for a call to succeed so the captured request can be inspected.
    ///
    let noConversations = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[]}}"#

    ///
    /// The bytes of an image, standing in for whatever the avatar endpoint serves.
    ///
    let imageBytes = #"<svg xmlns="http://www.w3.org/2000/svg"/>"#

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: MockRequesting) -> Server {
        Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
    }

    ///
    /// Build a server answering every request with the given body, status and header fields.
    ///
    private func makeServer(body: String, statusCode: Int = 200, headerFields: [String: String]? = nil) -> Server {
        makeServer(session: MockRequesting(string: body, statusCode: statusCode, headerFields: headerFields))
    }

    ///
    /// Build a server answering every request with an image of the given media type.
    ///
    private func makeImageServer(contentType: String = "image/svg+xml") -> Server {
        makeServer(body: imageBytes, headerFields: ["Content-Type": contentType])
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

    @Test("Conversation Listing Targets The Room Endpoint")
    func conversationsPath() async throws {
        let session = MockRequesting(string: noConversations)
        _ = try await makeServer(session: session).conversations()

        let (path, query) = try captured(from: session)

        // The server's API calls a conversation a room, and the listing is served by version 4 of it.
        #expect(path == "/ocs/v2.php/apps/spreed/api/v4/room")

        // Every query parameter this endpoint takes has a server side default, so none is sent at all.
        #expect(query.isEmpty)
    }

    @Test("Avatar Retrieval Carries The Token In Its Path")
    func avatarPath() async throws {
        let session = MockRequesting(string: imageBytes, headerFields: ["Content-Type": "image/svg+xml"])
        _ = try await makeServer(session: session).conversationAvatar("oypsiy6j")

        let (path, query) = try captured(from: session)

        // The avatar is served by version 1 of the API while the listing is served by version 4. The two are versioned independently, which makes this the easiest thing to get wrong.
        #expect(path == "/ocs/v2.php/apps/spreed/api/v1/room/oypsiy6j/avatar")
        #expect(query.isEmpty)
    }

    @Test("Dark Avatar Retrieval Targets The Dedicated Sub Route")
    func darkAvatarPath() async throws {
        let session = MockRequesting(string: imageBytes, headerFields: ["Content-Type": "image/svg+xml"])
        _ = try await makeServer(session: session).conversationAvatar("oypsiy6j", darkTheme: true)

        let (path, query) = try captured(from: session)

        // The endpoint also accepts a query parameter for this, which is deliberately not used: the fixture tree is keyed by path and drops the query, so both appearances would otherwise collapse into one directory.
        #expect(path == "/ocs/v2.php/apps/spreed/api/v1/room/oypsiy6j/avatar/dark")
        #expect(query.isEmpty)
    }

    @Test("Conversation Listing Is An Authenticated OCS Request")
    func requestHeaders() async throws {
        let session = MockRequesting(string: noConversations)
        _ = try await makeServer(session: session).conversations()

        let request = try #require(session.requests.first)
        let headers = request.allHTTPHeaderFields

        #expect(request.httpMethod == "GET")
        #expect(headers?["Accept"] == "application/json")
        #expect(headers?["User-Agent"] == "RainmakerTests")
        #expect(headers?["Authorization"] == "Basic \(Data("admin:admin".utf8).base64EncodedString())")

        // The Talk API is reachable through OCS, so the header announcing that has to be sent.
        #expect(headers?["OCS-APIRequest"] == "true")
    }

    @Test("Avatar Retrieval Announces That It Expects No Payload")
    func avatarRequestHeaders() async throws {
        let session = MockRequesting(string: imageBytes, headerFields: ["Content-Type": "image/svg+xml"])
        _ = try await makeServer(session: session).conversationAvatar("oypsiy6j")

        let request = try #require(session.requests.first)
        let headers = request.allHTTPHeaderFields

        // The response is an image rather than an OCS payload, so announcing JSON as every other request does would be a lie. This is also what makes the recorded fixture a binary one.
        #expect(headers?["Accept"] == "*/*")
        #expect(headers?["Authorization"] == "Basic \(Data("admin:admin".utf8).base64EncodedString())")
    }

    @Test("Avatar Retrieval Requests A Fresh Image", arguments: [false, true])
    func avatarRequestFreshness(darkTheme: Bool) async throws {
        let session = MockRequesting(string: imageBytes, headerFields: ["Content-Type": "image/svg+xml"])
        _ = try await makeServer(session: session).conversationAvatar("oypsiy6j", darkTheme: darkTheme)

        let request = try #require(session.requests.first)

        // The server permits caching an avatar for a day and marks it immutable, and a `URLSession` keeps an in memory cache even when it is configured as ephemeral. Retrieving an avatar is an explicit act by the caller, so it must reach the server rather than be answered from that cache. Both appearances are checked because each is a route of its own.
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    // MARK: - Credentials

    @Test("Conversation Listing Requires Credentials")
    func requireCredentials() async throws {
        let session = MockRequesting(string: noConversations)
        let server = Server(address: serverAddress, password: nil, user: nil, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.conversations()
        }

        // Credentials are required, so the call fails before any network request is made.
        #expect(session.requests.isEmpty)
    }

    @Test("Avatar Retrieval Requires Credentials")
    func requireAvatarCredentials() async throws {
        let session = MockRequesting(string: imageBytes)
        let server = Server(address: serverAddress, password: nil, user: nil, session: session, userAgent: "RainmakerTests")

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.conversationAvatar("oypsiy6j")
        }

        #expect(session.requests.isEmpty)
    }

    // MARK: - Availability

    @Test("Unavailable App Is Not Found")
    func unavailableApp() async throws {
        // Without the Talk app installed and enabled the OCS route does not exist, which the server reports with an envelope of its own rather than with the app's.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":998,"message":"Invalid query, please check the syntax."},"data":[]}}"#
        let server = makeServer(body: body, statusCode: 404)

        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.conversations()
        }
    }

    @Test("Unknown Conversation Is Not Found")
    func unknownConversation() async throws {
        // A conversation which does not exist, or which this account cannot reach, is answered with the very same status as an absent app, which is why the two are deliberately not told apart.
        let body = #"<?xml version="1.0"?><ocs><meta><status>failure</status><statuscode>404</statuscode></meta></ocs>"#
        let server = makeServer(body: body, statusCode: 404)

        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.conversationAvatar("zzzzzzzz")
        }
    }

    @Test("Rejected Credentials Are Reported As A Status")
    func rejectedCredentials() async throws {
        // A revoked app password is not the same as an absent app, so it must not collapse into a not found error.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":997,"message":"Current user is not logged in"},"data":[]}}"#
        let server = makeServer(body: body, statusCode: 401)

        await #expect(throws: RainmakerError.unexpectedStatus(code: 401)) {
            _ = try await server.conversations()
        }
    }

    @Test("Failed OCS Envelope Is A Decoding Failure")
    func failedEnvelope() async throws {
        // A success status carrying a failed envelope is what OCS answers with in some error cases, so the envelope's own status has to be checked rather than trusted.
        let body = #"{"ocs":{"meta":{"status":"failure","statuscode":500,"message":"Something went wrong"},"data":[]}}"#
        let server = makeServer(body: body)

        await #expect {
            _ = try await server.conversations()
        } throws: { error in
            guard case let RainmakerError.responseDecodingFailed(reason: reason) = error else {
                return false
            }

            return reason.contains("500") && reason.contains("Something went wrong")
        }
    }

    @Test("Malformed Success Response Is A Decoding Failure")
    func malformedResponse() async throws {
        let server = makeServer(body: #"{"unexpected":true}"#)

        // A body which is not an OCS envelope must surface as an error rather than as an empty listing.
        await #expect(throws: (any Error).self) {
            _ = try await server.conversations()
        }
    }

    // MARK: - Decoding

    @Test("Conversations Decode From What A Live Server Sends")
    func decodesConversation() async throws {
        // Verbatim what a live server sends, trimmed to a single conversation. Everything this library does not model, from the permission bit fields to the whole nested last message, has to be ignored rather than break the listing.
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[{"id":2,"token":"by9jp6mr","type":6,"name":"Note to self","displayName":"Note to self","objectType":"note_to_self","objectId":"admin","participantType":1,"participantFlags":0,"readOnly":0,"hasPassword":false,"hasCall":false,"callStartTime":0,"canStartCall":false,"lastActivity":1700000000,"lastReadMessage":5,"unreadMessages":3,"unreadMention":true,"unreadMentionDirect":false,"isFavorite":true,"canLeaveConversation":false,"canDeleteConversation":true,"notificationLevel":1,"lobbyState":0,"lobbyTimer":0,"lastPing":0,"sessionId":"0","sipEnabled":0,"actorType":"users","actorId":"admin","attendeeId":2,"permissions":510,"attendeePin":"","description":"A place for your private notes","lastCommonReadMessage":5,"listable":0,"messageExpiration":0,"avatarVersion":"Rw2KnG5yXX5AdMzz","isCustomAvatar":true,"isArchived":false,"tagIds":[],"attributes":0,"lastMessage":{"id":5,"token":"by9jp6mr","actorDisplayName":"","timestamp":1700000000,"message":"System created the conversation","systemMessage":"conversation_created"}}]}}"#
        let conversation = try #require(try await makeServer(body: body).conversations().first)

        #expect(conversation.id == 2)
        #expect(conversation.token == "by9jp6mr")
        #expect(conversation.displayName == "Note to self")
        #expect(conversation.avatarVersion == "Rw2KnG5yXX5AdMzz")
        #expect(conversation.unreadMessages == 3)
        #expect(conversation.unreadMention)

        // The raw `6` the server sends is meaningless on its own, which is the whole reason the kind is modelled as a case.
        #expect(conversation.type == .noteToSelf)

        // The server sends whole seconds since the Unix epoch, which the model converts itself rather than leaning on a decoder's date strategy.
        #expect(conversation.lastActivity == Date(timeIntervalSince1970: 1_700_000_000))

        #expect(conversation.description == "Note to self")
        #expect(conversation.debugDescription == "#2 (by9jp6mr): Note to self")
    }

    @Test("Unknown Conversation Kind Does Not Fail The Listing")
    func decodesUnknownType() async throws {
        // A kind introduced by a future release of the Talk app must not take the whole listing down with it, which a strict enum would.
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[{"id":9,"token":"aaaabbbb","type":99,"displayName":"From the future","lastActivity":1700000000,"unreadMessages":0,"unreadMention":false,"avatarVersion":"00000000"}]}}"#
        let conversations = try await makeServer(body: body).conversations()

        #expect(conversations.count == 1)
        #expect(conversations.first?.type == .other(99))
        #expect(conversations.first?.token == "aaaabbbb")
    }

    @Test("Conversation Without Activity Decodes As The Epoch")
    func decodesAbsentActivity() async throws {
        // A conversation nothing has happened in yet is reported as a zero timestamp rather than as an absent field, which still sorts as the oldest.
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":[{"id":9,"token":"aaaabbbb","type":2,"displayName":"Fresh","lastActivity":0,"unreadMessages":0,"unreadMention":false,"avatarVersion":"00000000"}]}}"#
        let conversation = try #require(try await makeServer(body: body).conversations().first)

        #expect(conversation.lastActivity == Date(timeIntervalSince1970: 0))
    }

    @Test("Avatar Carries The Bytes And The Type The Server Sent")
    func decodesAvatar() async throws {
        let avatar = try await makeImageServer().conversationAvatar("oypsiy6j")

        #expect(avatar.data == Data(imageBytes.utf8))

        // Every generated icon and every emoji avatar is an SVG document rather than a bitmap, so the type is what a client has to look at before rendering.
        #expect(avatar.contentType == "image/svg+xml")
    }

    @Test("Avatar Of An Unstated Type Is A Decoding Failure")
    func avatarWithoutContentType() async throws {
        let server = makeServer(body: imageBytes)

        // Guessing between a bitmap and an SVG document would be worse than reporting that the server did not say.
        await #expect {
            _ = try await server.conversationAvatar("oypsiy6j")
        } throws: { error in
            guard case let RainmakerError.responseDecodingFailed(reason: reason) = error else {
                return false
            }

            return reason.contains("type")
        }
    }
}
