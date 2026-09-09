// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The kind of a Nextcloud Talk conversation.
///
/// This is the ``Conversation/type`` of a conversation as listed by ``Server/conversations()``, and it is what tells a conversation between two people apart from a group, from a public link conversation, and from the ones the server maintains on its own.
///
/// The kinds are those of the Talk app, whose raw values are neither consecutive nor self-explanatory, which is why they are modelled as cases rather than surfaced as the plain number the server sends.
///
public enum ConversationType: Model, Decodable, Equatable {
    ///
    /// A conversation between the authenticated user and exactly one other person, equalling the raw representation as `1`.
    ///
    /// Such a conversation is named by the server rather than by its participants, so its ``Conversation/displayName`` carries the other person's name.
    ///
    case oneToOne

    ///
    /// A conversation between a group of people, equalling the raw representation as `2`.
    ///
    case group

    ///
    /// A conversation which can be joined through a public link, equalling the raw representation as `3`.
    ///
    /// The case is not named `public` because that is a Swift keyword, and a name needing backticks at every declaration is worse than a slightly longer one.
    ///
    case publicConversation

    ///
    /// The conversation the Talk app keeps its own release notes in, equalling the raw representation as `4`.
    ///
    /// Every account has one, it is read only, and it is created without the user asking for it, which is why a client presenting a conversation list may well want to leave it out.
    ///
    case changelog

    ///
    /// What is left of a ``oneToOne`` conversation after the other person's account was removed, equalling the raw representation as `5`.
    ///
    case formerOneToOne

    ///
    /// The conversation an account has with itself, equalling the raw representation as `6`.
    ///
    /// The server creates it on demand and identifies it through the `note_to_self` object type.
    ///
    case noteToSelf

    ///
    /// A kind this library does not know about, carrying the raw representation the server sent.
    ///
    /// This exists so that a kind introduced by a future version of the Talk app cannot fail the decoding of a whole conversation, and with it of the entire listing. Anything switching over this enum has to expect it. The server's own marker for a kind it cannot name is `-1`, which lands here as well.
    ///
    case other(Int)

    ///
    /// Derive a case from the raw value returned by the server.
    ///
    /// Every unknown value becomes ``other(_:)`` rather than failing, mirroring how ``MembershipLevel/init(_:)`` absorbs the raw values of a membership level.
    ///
    public init(_ rawValue: Int) {
        switch rawValue {
            case 1:
                self = .oneToOne
            case 2:
                self = .group
            case 3:
                self = .publicConversation
            case 4:
                self = .changelog
            case 5:
                self = .formerOneToOne
            case 6:
                self = .noteToSelf
            default:
                self = .other(rawValue)
        }
    }

    // MARK: - Decodable

    ///
    /// Decode a kind from the plain number the server sends for it.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Int.self))
    }

    // MARK: - Encodable

    ///
    /// Encode a kind as the name of its case, so that the encoded form is readable rather than a number whose meaning has to be looked up.
    ///
    /// A kind this library does not know about has no name to encode, so ``other(_:)`` falls back to the raw number the server sent. This asymmetry mirrors ``MembershipLevel/encode(to:)``, which likewise encodes its named cases as strings and its only value-carrying case as a number.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
            case .oneToOne:
                try container.encode("oneToOne")
            case .group:
                try container.encode("group")
            case .publicConversation:
                try container.encode("publicConversation")
            case .changelog:
                try container.encode("changelog")
            case .formerOneToOne:
                try container.encode("formerOneToOne")
            case .noteToSelf:
                try container.encode("noteToSelf")
            case let .other(type):
                try container.encode(type)
        }
    }
}
