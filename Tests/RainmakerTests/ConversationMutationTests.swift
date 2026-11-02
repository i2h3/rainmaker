// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About searching the users of the server, starting a Talk conversation with one of them, and sending messages and files into a conversation as the authenticated user.
///
/// The fixtures backing this suite are recorded like those of ``ConversationsTests``, against a container with the Talk app installed. Besides the conversation that suite asserts on, ``FixtureProvisioner`` seeds a second account for this one, because the search needs somebody to find and a one-to-one conversation needs somebody to talk to. Accounts live outside the account's files, so the baseline reset between recordings neither removes nor restores it, which is why the seeding is idempotent.
///
/// Every test removes what it creates where Talk lets it. Talk refuses to delete a one-to-one conversation unless an administrator allowed it, so the account leaves the conversation it started instead, which takes it out of its listing while Talk keeps it for the other participant. A message cannot be taken back, because sending one reports nothing to delete, so the messages and files this suite sends stay in the seeded conversation, which is harmless because ``ConversationsTests`` asserts nothing about its messages. The file itself lands in the account's files, which the baseline reset removes again.
///
/// The token of a conversation is taken from a listing or a creation recorded in the same test rather than pinned, because it is part of the path of every further request about that conversation and the server assigns it anew in every deployment. Every request of a test differs in method or path, which is what lets the fixture tree replay them. The file sent is stamped with a fixed modification date, because the name it is uploaded under is derived from it.
///
/// Whether a file can be sent depends on the release of the Talk app rather than on the server, so that test records the capabilities first and branches on ``Talk/storesAttachmentsPerConversation``. How the requests are built and how the statuses Talk may answer with map onto ``RainmakerError`` is covered by ``ConversationWritingRequestTests`` instead.
///
/// Calls go through ``Serving``, whose requirements have no default arguments, so every argument is spelled out.
///
@Suite("Conversation Mutations") struct ConversationMutationTests: ServerTesting {
    ///
    /// The name of the conversation ``FixtureProvisioner`` seeds, which is what makes it findable without relying on a token, as in ``ConversationsTests``.
    ///
    let seededConversation = "Rainmaker"

    ///
    /// The second account ``FixtureProvisioner`` seeds, which the search finds and the one-to-one conversation is started with.
    ///
    let seededUser = User(id: "alice", displayName: "Alice")

    ///
    /// The moment the file this suite sends is stamped with, pinned because the name it is uploaded under is derived from it.
    ///
    let modification = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Search Users", arguments: ServerVersion.allCases)
    func searchUsers(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let users = try await server.searchUsers(seededUser.id)

        // Whatever else a release finds for the term, the seeded account is among the results with the display name it was created with.
        #expect(users.contains(seededUser))
    }

    @Test("Create Conversation", arguments: ServerVersion.allCases)
    func createConversation(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let conversation = try await server.createConversation(with: seededUser.id)

        // A one-to-one conversation is named after the other participant from the point of view of each of them.
        #expect(conversation.type == .oneToOne)
        #expect(conversation.displayName == seededUser.displayName)
        #expect(conversation.token.isEmpty == false)

        // Talk answers the deletion of a one-to-one conversation with `400` unless an administrator allowed it, so the account leaves the conversation instead, which takes it out of its listing just the same. The request goes through the session the server records and replays with, so that it is part of the fixtures as well.
        let concrete = try #require(server as? Server)
        let request = try concrete.makeOCSRequest(for: "apps/spreed/api/v4/room/\(conversation.token)/participants/self", method: .delete)
        let (_, urlResponse) = try await concrete.session.data(for: request)

        #expect((urlResponse as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test("Send Message", arguments: ServerVersion.allCases)
    func sendMessage(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let conversations = try await server.conversations()
        let conversation = try #require(conversations.first { $0.displayName == seededConversation })

        try await server.sendMessage("Hello from Rainmaker", toConversation: conversation.token)
    }

    @Test("Send File", arguments: ServerVersion.allCases)
    func sendFile(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let talk = try #require(try await server.capabilities().get(Talk.self))
        let conversations = try await server.conversations()
        let conversation = try #require(conversations.first { $0.displayName == seededConversation })

        let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        let file = source.appendingCompatibility(component: "Rainmaker.txt")
        try Data("Rainmaker\n".utf8).write(to: file)

        // The name the file is uploaded under in the draft folder is derived from the conversation, the file name, the size and the modification date, so the latter is pinned to keep the recorded upload replayable.
        try FileManager.default.setAttributes([.modificationDate: modification], ofItemAtPath: file.compatibilityPath())

        if talk.storesAttachmentsPerConversation {
            try await server.sendFile(file, toConversation: conversation.token, caption: "Rainmaker")
        } else {
            // Releases before Talk 24 route no draft folder, which the server answers with `404` and which therefore surfaces as not found before anything is uploaded.
            await #expect(throws: RainmakerError.notFound) {
                try await server.sendFile(file, toConversation: conversation.token, caption: "Rainmaker")
            }
        }
    }
}
