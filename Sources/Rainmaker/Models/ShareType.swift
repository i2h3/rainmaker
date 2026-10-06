// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A kind of share a file can be part of on the server.
///
/// This is what ``Note/shareTypes`` lists for a note, one entry per kind of share the note's file is part of, and what ``Note/isShared`` summarizes.
///
/// The kinds are those of the server's sharing subsystem, whose raw values are neither consecutive nor self-explanatory, which is why the known ones are offered as named constants such as ``user`` and ``link``.
/// Unlike ``ConversationType`` this is a struct wrapping the plain number rather than an enum: a kind introduced by a future version of the server or by an app still decodes and keeps its number, and comparing against the constants keeps working without a catch-all case to switch over.
///
public struct ShareType: RawRepresentable, Model, Hashable, Decodable, CustomStringConvertible {
    ///
    /// The number the server uses for this kind of share.
    ///
    public let rawValue: Int

    ///
    /// Wrap the number the server uses for a kind of share, whether or not this library has a named constant for it.
    ///
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    ///
    /// A share with an individual user of the same server, equalling the raw representation as `0`.
    ///
    public static let user = ShareType(rawValue: 0)

    ///
    /// A share with a group of users of the same server, equalling the raw representation as `1`.
    ///
    public static let group = ShareType(rawValue: 1)

    ///
    /// A public link share, equalling the raw representation as `3`.
    ///
    public static let link = ShareType(rawValue: 3)

    ///
    /// A share with an email address, equalling the raw representation as `4`.
    ///
    public static let email = ShareType(rawValue: 4)

    ///
    /// A federated share with a user of another server, equalling the raw representation as `6`.
    ///
    public static let federated = ShareType(rawValue: 6)

    ///
    /// A share with a Nextcloud Talk conversation, equalling the raw representation as `10`.
    ///
    public static let room = ShareType(rawValue: 10)

    ///
    /// A share with a board of the Deck app, equalling the raw representation as `12`.
    ///
    public static let deck = ShareType(rawValue: 12)

    ///
    /// A share through the ScienceMesh federation, equalling the raw representation as `15`.
    ///
    public static let scienceMesh = ShareType(rawValue: 15)

    // MARK: - Decodable

    ///
    /// Decode a kind of share from the plain number the server sends for it.
    ///
    /// Every number decodes, including those without a named constant, so that a kind of share this library does not know about cannot fail the decoding of a whole ``Note``.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(Int.self))
    }

    // MARK: - Encodable

    ///
    /// Encode a kind of share as the plain number the server uses for it.
    ///
    /// Unlike ``ConversationType/encode(to:)`` this does not encode a name, because a struct wrapping a number has no case name to fall back on and the number is the only representation every value has.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a kind of share.
    ///
    public var description: String {
        switch self {
            case .user:
                "user"
            case .group:
                "group"
            case .link:
                "link"
            case .email:
                "email"
            case .federated:
                "federated"
            case .room:
                "room"
            case .deck:
                "deck"
            case .scienceMesh:
                "scienceMesh"
            default:
                "\(rawValue)"
        }
    }
}
