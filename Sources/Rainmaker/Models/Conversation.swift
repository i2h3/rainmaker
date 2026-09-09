// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single Nextcloud Talk conversation the authenticated user takes part in.
///
/// Conversations are listed through ``Server/conversations()`` and their image is retrieved through ``Server/conversationAvatar(_:darkTheme:)``. They are provided by the Talk app (`spreed`) which, like the notes app, is not part of a Nextcloud installation and has to be installed separately. Whether it is available can be checked in advance via the ``Talk`` capability, e.g. `try await capabilities().contains(Talk.self)`.
///
/// The server's own API calls a conversation a "room", which is why the endpoint behind ``Server/conversations()`` is `apps/spreed/api/v4/room`, while its user interface calls it a conversation. This type follows the latter.
///
/// Only ``token`` addresses a conversation in the server's API. ``id`` is a plain number unique per server and is what makes this type `Identifiable`, but every other Talk endpoint takes the token in its path instead.
///
/// The server sends far more about a conversation than is modelled here, because this type exists to list conversations rather than to take part in one. The last message, the read markers (`lastReadMessage`, `lastCommonReadMessage`), the permission bit fields (`permissions`, `attendeePermissions`, `defaultPermissions`, `callPermissions`), the attendee and session details (`attendeeId`, `actorId`, `actorType`, `sessionId`, `lastPing`), the call state (`hasCall`, `callFlag`, `callStartTime`, `callRecording`, `canStartCall`), `isCustomAvatar`, the lobby, breakout room, message expiration, SIP and federation fields as well as `name`, `description`, `listable`, `notificationLevel`, `participantType`, `hasPassword`, `isFavorite`, `isArchived`, `isImportant`, `isSensitive` and `tagIds` are intentionally not modelled, as chatting, calling and moderating are out of scope. A client needing any of them can build its own request with ``Server/makeOCSRequest(for:method:queryItems:)``.
///
public struct Conversation: Model, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the conversation, unique per server.
    ///
    /// This is not what addresses a conversation in the server's API; ``token`` is. It is modelled all the same because it is what makes a conversation `Identifiable` and what a client can key its own storage by.
    ///
    public let id: Int

    ///
    /// The opaque token identifying the conversation, e.g. `"oypsiy6j"`.
    ///
    /// Every Talk endpoint beyond the listing takes this in its path, which is why it is also what ``Server/conversationAvatar(_:darkTheme:)`` and any request built with ``Server/makeOCSRequest(for:method:queryItems:)`` are given.
    ///
    public let token: String

    ///
    /// What kind of conversation this is.
    ///
    public let type: ConversationType

    ///
    /// The name to present to the user.
    ///
    /// The server resolves this for the authenticated user, so a ``ConversationType/oneToOne`` conversation carries the other person's name even though the conversation itself is stored without one. It is localized to the account's language for the conversations the server maintains on its own, such as ``ConversationType/changelog`` and ``ConversationType/noteToSelf``.
    ///
    public let displayName: String

    ///
    /// The server's version marker for the conversation's avatar, e.g. `"b0135871"`.
    ///
    /// A change invalidates a cached image, but an unchanged marker is no promise that the image is unchanged, and for a ``ConversationType/oneToOne`` conversation it promises nothing at all.
    /// The server derives the marker of such a conversation from the path of a generic icon, which makes it one and the same value for every one-to-one conversation on that server, while the avatar endpoint answers with the other person's current profile picture. Nothing that person does to their picture moves this value.
    ///
    /// So treat this as a hint to invalidate with, never as a key to cache under. Cache images between displays, refreshing them when this marker changes and periodically even when it does not, for example once a day.
    /// Keep separate entries for each server, account, conversation token and appearance. The appearance belongs in the key because the marker of an emoji avatar is derived from its light variant alone, so both appearances of one conversation share a single value.
    /// ``Server/conversationAvatar(_:darkTheme:)`` bypasses the local HTTP cache so that an explicit refresh can retrieve updated bytes.
    ///
    public let avatarVersion: String

    ///
    /// The moment of the last activity in the conversation.
    ///
    /// This corresponds to the server's `lastActivity` field, a number of whole seconds since the Unix epoch in the UTC time zone.
    /// The conversion happens in ``init(from:)`` rather than through a decoder's date strategy, so that this type decodes correctly no matter which `JSONDecoder` a downstream project passes it to.
    ///
    /// A conversation without any activity yet is reported as `0` by the server and therefore surfaces as `Date(timeIntervalSince1970: 0)` rather than as `nil`, which still sorts as the oldest.
    ///
    public let lastActivity: Date

    ///
    /// The number of chat messages in the conversation the authenticated user has not read yet.
    ///
    public let unreadMessages: Int

    ///
    /// Whether the authenticated user was mentioned in the conversation since they last visited it.
    ///
    /// This includes a mention of everyone rather than only a direct one, which the server reports separately in a field this type does not model.
    ///
    public let unreadMention: Bool

    ///
    /// The keys a conversation is decoded from, which are the names the server sends.
    ///
    /// Unlike ``Note`` or ``Collective``, this type needs no separate set of encoding keys: no property is renamed here, so the two would be identical and the synthesized `Encodable` conformance already encodes under the property names.
    ///
    private enum CodingKeys: String, CodingKey {
        case id
        case token
        case type
        case displayName
        case avatarVersion
        case lastActivity
        case unreadMessages
        case unreadMention
    }

    // MARK: - Decodable

    ///
    /// Decode a conversation from the server's payload.
    ///
    /// Every modelled field is required: the listing endpoint declares all of them for every server version this library supports, so a missing one means a response this type cannot describe. Whatever else the payload carries is ignored, which is what lets one client read the conversations of servers running different releases of the Talk app.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        token = try container.decode(String.self, forKey: .token)
        type = try container.decode(ConversationType.self, forKey: .type)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarVersion = try container.decode(String.self, forKey: .avatarVersion)
        unreadMessages = try container.decode(Int.self, forKey: .unreadMessages)
        unreadMention = try container.decode(Bool.self, forKey: .unreadMention)

        // Decoding into a `TimeInterval` rather than an integer avoids the trap an out of range value would cause on the platforms where `Int` is only 32 bits wide.
        let secondsSince1970 = try container.decode(TimeInterval.self, forKey: .lastActivity)
        lastActivity = Date(timeIntervalSince1970: secondsSince1970)
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a conversation.
    ///
    public var description: String {
        displayName
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a conversation.
    ///
    public var debugDescription: String {
        "#\(id) (\(token)): \(displayName)"
    }
}
