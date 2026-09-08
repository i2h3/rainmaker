// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The level a member holds in the team backing a collective.
///
/// This is the ``Collective/level`` of a collective as listed by ``Server/collectives()``, and it says what the authenticated user is allowed to do with it beyond what ``Collective/canEdit``, ``Collective/canShare`` and ``Collective/canLeave`` already answer directly.
///
/// The levels are those of the Teams app a collective is backed by, whose raw values are neither consecutive nor self-explanatory, which is why they are modelled as cases rather than surfaced as the plain number the server sends.
///
public enum MembershipLevel: Model, Decodable, Equatable {
    ///
    /// No membership at all, equalling the raw representation as `0`.
    ///
    case none

    ///
    /// An ordinary member, equalling the raw representation as `1`.
    ///
    case member

    ///
    /// A moderator, equalling the raw representation as `4`.
    ///
    case moderator

    ///
    /// An administrator, equalling the raw representation as `8`.
    ///
    case admin

    ///
    /// The owner, equalling the raw representation as `9`.
    ///
    case owner

    ///
    /// A level this library does not know about, carrying the raw representation the server sent.
    ///
    /// This exists so that a level introduced by a future version of the server cannot fail the decoding of a whole collective. Anything switching over this enum has to expect it.
    ///
    case other(Int)

    ///
    /// Derive a case from the raw value returned by the server.
    ///
    /// Every unknown value becomes ``other(_:)`` rather than failing, mirroring how ``AvailableQuota/init(_:)`` absorbs the raw values of a quota.
    ///
    public init(_ rawValue: Int) {
        switch rawValue {
            case 0:
                self = .none
            case 1:
                self = .member
            case 4:
                self = .moderator
            case 8:
                self = .admin
            case 9:
                self = .owner
            default:
                self = .other(rawValue)
        }
    }

    // MARK: - Decodable

    ///
    /// Decode a level from the plain number the server sends for it.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Int.self))
    }

    // MARK: - Encodable

    ///
    /// Encode a level as the name of its case, so that the encoded form is readable rather than a number whose meaning has to be looked up.
    ///
    /// A level this library does not know about has no name to encode, so ``other(_:)`` falls back to the raw number the server sent. This asymmetry mirrors ``AvailableQuota/encode(to:)``, which likewise encodes its named cases as strings and its only value-carrying case as a number.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
            case .none:
                try container.encode("none")
            case .member:
                try container.encode("member")
            case .moderator:
                try container.encode("moderator")
            case .admin:
                try container.encode("admin")
            case .owner:
                try container.encode("owner")
            case let .other(level):
                try container.encode(level)
        }
    }
}
