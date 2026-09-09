// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single collective the authenticated user is a member of.
///
/// Collectives are listed through ``Server/collectives()`` and their pages through ``Server/pages(inCollective:)``. They are provided by the Collectives app which, like the notes app, is not part of a Nextcloud installation and has to be installed separately.
///
/// Unlike every other app this library covers, Collectives advertises no capability, so its availability cannot be checked through ``Server/capabilities()`` the way the ``Notes`` or ``Activity`` capabilities allow. Call ``Server/navigation()`` and look for the entry whose ``NavigationItem/id`` is `"collectives"` instead, which the server advertises exactly while the app is enabled for the user.
///
/// Every collective is backed by a team, which is what ``teamId`` refers to and what makes its content owned by a group rather than by a single user.
///
/// The server sends more about a collective than is modelled here. The fields describing a public share of it (`isPageShare`, `sharePageId` and `shareEditable`) are omitted because this endpoint never populates them: only the public share flow, which is out of scope, does. So is `trashTimestamp`, because the listing returns non-trashed collectives only. The per-user interface preferences (`userPageOrder`, `userShowMembers`, `userShowRecentPages` and `userFavoritePages`) are omitted as settings of the web interface rather than properties of the collective, and the permission thresholds (`editPermissionLevel`, `sharePermissionLevel`) as well as `pageMode` because ``canEdit`` and ``canShare`` already answer what a client asks them for.
///
public struct Collective: Model, Hashable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the collective, unique per server.
    ///
    /// This is what ``Server/pages(inCollective:)`` takes to list the pages within this collective.
    ///
    public let id: Int

    ///
    /// The human-readable name of the collective, which the server also uses as the name of the folder its pages are stored in.
    ///
    public let name: String

    ///
    /// The url-safe form of ``name`` the server uses when addressing the collective in a link, e.g. `"cookbook"`.
    ///
    /// This is `nil` on a server whose Collectives app predates slugs, which is why a client which builds links has to be prepared to fall back to ``name``.
    ///
    public let slug: String?

    ///
    /// The emoji the collective is decorated with, e.g. `"📗"`. `nil` when it has none.
    ///
    public let emoji: String?

    ///
    /// The identifier of the team owning the collective and its content.
    ///
    /// This corresponds to the server's `circleId` field, which is what the Teams app was called before it was renamed.
    ///
    public let teamId: String

    ///
    /// The level the authenticated user holds in the team backing the collective.
    ///
    /// ``canEdit``, ``canShare`` and ``canLeave`` are what the server derives from this, so a client deciding whether to offer an action should prefer those over comparing levels itself.
    ///
    public let level: MembershipLevel

    ///
    /// Whether the authenticated user may change the pages of the collective.
    ///
    public let canEdit: Bool

    ///
    /// Whether the authenticated user may share the collective.
    ///
    public let canShare: Bool

    ///
    /// Whether the authenticated user may leave the collective.
    ///
    /// This is `false` for the last remaining administrator, who has to hand the collective over or delete it instead.
    ///
    public let canLeave: Bool

    ///
    /// The token of the public share of the whole collective. `nil` while it is not shared publicly.
    ///
    /// This is always a share of the collective itself: the listing looks up shares whose page identifier is zero, so a share of a single page never surfaces here.
    ///
    public let shareToken: String?

    ///
    /// The keys a collective is decoded from, which are the names the server sends. Encoding uses the separate encoding keys below so that the server's naming does not leak into the encoded form.
    ///
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case emoji
        case teamId = "circleId"
        case level
        case canEdit
        case canShare
        case canLeave
        case shareToken
    }

    // MARK: - Encodable

    ///
    /// The keys a collective is encoded under, which are the property names rather than the names the server sends.
    ///
    /// Encoding deliberately does not reuse ``CodingKeys``: those exist to read the server's payload and carry its naming, which would leak back out into anything this library encodes. Keeping the two apart is what makes the encoded form match the model a Swift caller sees, including where a property was renamed for clarity such as ``teamId`` over the server's `circleId`.
    ///
    private enum EncodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case emoji
        case teamId
        case level
        case canEdit
        case canShare
        case canLeave
        case shareToken
    }

    ///
    /// Encode a collective under its property names, so that the encoded form mirrors this type rather than the server's payload.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(slug, forKey: .slug)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(teamId, forKey: .teamId)
        try container.encode(level, forKey: .level)
        try container.encode(canEdit, forKey: .canEdit)
        try container.encode(canShare, forKey: .canShare)
        try container.encode(canLeave, forKey: .canLeave)
        try container.encode(shareToken, forKey: .shareToken)
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a collective.
    ///
    public var description: String {
        name
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a collective.
    ///
    public var debugDescription: String {
        "#\(id) (\(teamId)): \(name)"
    }
}
