// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About listing the Talk conversations of the authenticated user and retrieving their images.
///
/// The fixtures backing this suite are recorded against a live container with the Talk app installed, which `FixtureOrchestrator` declares alongside the notes app. Talk keeps its conversations outside the account's files and mounts nothing into them, which is what makes recording possible here while ``CollectivesTests`` has to do without it.
///
/// The conversation asserted on is the one ``FixtureProvisioner`` seeds, and it is looked up by name rather than by token, identifier or position. That is not a convenience: a plain Talk installation creates conversations of its own whose names are localized to the account's language, whose unread counts follow the release of the app rather than of the server, and whose very existence differs between releases. Nothing about them is worth asserting, so nothing here does.
///
/// The tokens the fixtures carry are the ones the recorded server assigned, because a token is also part of the path the avatar of a conversation is fetched under and therefore of where its fixture lives. See ``FixtureCanonicalizer``.
///
/// How a request is built, how an absent app, an unknown conversation and an unknown conversation kind surface, and how the payloads decode is covered by ``ConversationsRequestTests`` instead, which drives a mock rather than the fixture tree.
///
@Suite("Conversations") struct ConversationsTests: ServerTesting {
    ///
    /// The name of the conversation ``FixtureProvisioner`` seeds, which is what makes it findable without relying on a token.
    ///
    let seededConversation = "Rainmaker"

    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.conversations()
        }
    }

    @Test("Fetch", arguments: ServerVersion.allCases)
    func fetch(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let conversations = try await server.conversations()

        // Downstream projects rely on the count to learn whether and how many conversations exist.
        #expect(conversations.isEmpty == false)

        // Whatever a given release of the Talk app creates by itself, every conversation is addressable and cacheable, which is what a client surfacing them needs.
        #expect(conversations.allSatisfy { $0.id > 0 })
        #expect(conversations.allSatisfy { $0.token.isEmpty == false })
        #expect(conversations.allSatisfy { $0.avatarVersion.isEmpty == false })

        // Every kind a supported server sends has a case of its own, so anything falling through to the unknown one means the enum is behind.
        let unknownKinds = conversations.filter { conversation in
            if case .other = conversation.type {
                return true
            }

            return false
        }

        #expect(unknownKinds.isEmpty)

        // Looked up by name rather than by position or token: the tokens the server assigns differ per deployment.
        let conversation = try #require(conversations.first { $0.displayName == seededConversation })

        #expect(conversation.type == .group)
        #expect(conversation.unreadMessages == 0)
        #expect(conversation.unreadMention == false)
        #expect(conversation.description == seededConversation)
        #expect(conversation.debugDescription == "#\(conversation.id) (\(conversation.token)): \(seededConversation)")

        // Only that the activity decoded at all is asserted, never its value: ``FixtureCanonicalizer`` flattens it to a fixed moment because the recorded one is the time of the recording, and a recording run asserts against the live response rather than against what it persisted. The conversion from the whole seconds the server sends is pinned exactly in ``ConversationsRequestTests`` instead.
        #expect(conversation.lastActivity > Date(timeIntervalSince1970: 0))

        // Every account gets a conversation with itself, which is the one kind besides the seeded group conversation that every supported release creates alike.
        #expect(conversations.contains { $0.type == .noteToSelf })
    }

    @Test("Avatar", arguments: ServerVersion.allCases)
    func avatar(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let conversations = try await server.conversations()
        let conversation = try #require(conversations.first { $0.displayName == seededConversation })
        // The variant is named explicitly because ``ServerTesting/makeServer(user:password:serverVersion:testSourceCodeFile:testName:)`` hands out a ``Serving``, and the default lives on the concrete ``Server`` rather than on the protocol.
        let avatar = try await server.conversationAvatar(conversation.token, darkTheme: false)

        #expect(avatar.data.isEmpty == false)

        // Which image a conversation has is the server's decision, so only that it is an image at all can be asserted. A conversation nobody set a picture for gets a generated SVG document today, which is not a contract.
        #expect(avatar.contentType.hasPrefix("image/"))
    }
}
