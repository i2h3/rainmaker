// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single page within a collective.
///
/// Pages are listed through ``Server/pages(inCollective:)``, which returns every page of a collective at once, flat and fully recursive. The hierarchy is not assembled into a tree; it is reconstructed from ``parentId``, and ``subpageOrder`` says in which order a client should present the children of a page where the collective's members arranged them by hand.
///
/// Every page is a Markdown file in the folder of its ``Collective``, which is why ``fileName`` and ``filePath`` describe a location in the account's files rather than an abstract address. This models the page's metadata only: retrieving the Markdown itself is out of scope, and would mean reading that file over WebDAV.
///
/// The server sends more about a page than is modelled here. `filePathString` is omitted because it is a display string the web interface builds by joining the components of ``filePath`` with `" - "`, which a client can do itself and differently. `collectiveNameWithEmoji` is omitted because this endpoint leaves it empty. So are `trashTimestamp`, because the listing returns non-trashed pages only, and `shareToken`, because sharing individual pages is out of scope.
///
public struct CollectivePage: Model, Hashable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the page, which is the identifier of its file.
    ///
    /// This is what ``parentId``, ``subpageOrder`` and ``linkedPageIds`` refer to.
    ///
    public let id: Int

    ///
    /// The title of the page.
    ///
    /// For an ordinary page this is its file name without the Markdown extension. For the page at the root of a collective, the one whose ``isLandingPage`` is `true`, the server substitutes a localized title instead, so it reads in the language of the account rather than matching ``fileName``.
    ///
    public let title: String

    ///
    /// The url-safe form of ``title`` the server uses when addressing the page in a link, e.g. `"pancakes"`.
    ///
    /// This is `nil` on a server whose Collectives app predates slugs, which is why a client which builds links has to be prepared to fall back to ``title``.
    ///
    public let slug: String?

    ///
    /// The emoji the page is decorated with, e.g. `"🥞"`. `nil` when it has none.
    ///
    public let emoji: String?

    ///
    /// The name of the file backing the page, including its extension, e.g. `"Pancakes.md"`.
    ///
    /// A page which has subpages is stored as the index file of a folder and is therefore always named `"Readme.md"`, which is what ``isLandingPage`` and ``parentId`` are needed to tell apart.
    ///
    public let fileName: String

    ///
    /// The folder containing ``fileName``, relative to the root of the collective, e.g. `"Recipes"`.
    ///
    /// This is an empty string for a page sitting directly in the collective rather than in a subfolder of it.
    ///
    public let filePath: String

    ///
    /// The folder of the whole collective, relative to the account's files, e.g. `".Kollektive/Corporate"`. `nil` when the server does not report it.
    ///
    /// Together with ``filePath`` and ``fileName`` this is the complete location of the page's file in the account's files, which is what makes the Markdown reachable over WebDAV, for example through ``Server/enumerate(at:recursively:)->[Item]``. It is not a fixed name and not even a visible one: its first component defaults to a hidden folder whose name is derived from the account's locale, so a German account ends up with `".Kollektive"`. Asking the server rather than assuming is therefore the only way to reach a page's file, which is the same reason ``NotesSettings/notesPath`` exists.
    ///
    public let collectivePath: String?

    ///
    /// The identifier of the page this one is a subpage of, or `0` for the page at the root of the collective.
    ///
    /// Reassembling the hierarchy is a matter of grouping the returned pages by this, and ``isLandingPage`` is the readable form of the comparison against zero.
    ///
    public let parentId: Int

    ///
    /// Whether this is the page at the root of the collective, which every collective has exactly one of.
    ///
    /// Derived from ``parentId`` rather than sent by the server, because that comparison is what a client would otherwise have to know to write. It is also the page whose ``title`` is localized rather than derived from ``fileName``.
    ///
    public var isLandingPage: Bool {
        parentId == 0
    }

    ///
    /// The moment the page was last modified.
    ///
    /// This corresponds to the server's `timestamp` field, a number of whole seconds since the Unix epoch.
    /// The conversion happens in ``init(from:)`` rather than through a decoder's date strategy, so that this type decodes correctly no matter which `JSONDecoder` a downstream project passes it to.
    ///
    public let modification: Date

    ///
    /// The size of the page's file in bytes.
    ///
    public let size: UInt64

    ///
    /// Whether the page is presented using the full width of the window rather than a centered column.
    ///
    public let isFullWidth: Bool

    ///
    /// The identifiers of the tags applied to the page. Empty when it carries none.
    ///
    /// Resolving these to their names means listing the collective's tags, which is out of scope.
    ///
    public let tags: [Int]

    ///
    /// The identifiers of this page's subpages, in the order the collective's members arranged them.
    ///
    /// This is not necessarily complete: the server only records a page here once it has been placed deliberately, so a subpage which was never rearranged is missing from it while still being returned by ``Server/pages(inCollective:)`` with this page as its ``parentId``.
    ///
    public let subpageOrder: [Int]

    ///
    /// The identifiers of the pages this page links to. Empty when it links to none.
    ///
    /// Only links to pages within the same collective are recorded, which is what makes them resolvable against the same listing.
    ///
    public let linkedPageIds: [Int]

    ///
    /// The name of the user who last modified the page. `nil` when the server does not know.
    ///
    /// This corresponds to the server's `lastUserId` field. Use ``lastEditorDisplayName`` to present it.
    ///
    public let lastEditor: String?

    ///
    /// The display name of the user who last modified the page. `nil` when the server does not know.
    ///
    /// This corresponds to the server's `lastUserDisplayName` field.
    ///
    public let lastEditorDisplayName: String?

    ///
    /// The keys a page is decoded from, which are the names the server sends. Encoding uses the separate encoding keys below so that the server's naming does not leak into the encoded form.
    ///
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case slug
        case emoji
        case fileName
        case filePath
        case collectivePath
        case parentId
        case modification = "timestamp"
        case size
        case isFullWidth
        case tags
        case subpageOrder
        case linkedPageIds
        case lastEditor = "lastUserId"
        case lastEditorDisplayName = "lastUserDisplayName"
    }

    // MARK: - Decodable

    ///
    /// Decode a page from the server's payload.
    ///
    /// Written by hand only because of ``modification``: the server reports it as a number of whole seconds since the Unix epoch while every other date this library decodes is ISO 8601, and the shared decoder is configured for the latter. Converting here rather than switching a decoder's strategy keeps this type decodable by any `JSONDecoder`, including one a downstream project brings along.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        fileName = try container.decode(String.self, forKey: .fileName)
        filePath = try container.decode(String.self, forKey: .filePath)
        collectivePath = try container.decodeIfPresent(String.self, forKey: .collectivePath)
        parentId = try container.decode(Int.self, forKey: .parentId)
        size = try container.decode(UInt64.self, forKey: .size)
        isFullWidth = try container.decode(Bool.self, forKey: .isFullWidth)
        tags = try container.decode([Int].self, forKey: .tags)
        subpageOrder = try container.decode([Int].self, forKey: .subpageOrder)
        linkedPageIds = try container.decode([Int].self, forKey: .linkedPageIds)
        lastEditor = try container.decodeIfPresent(String.self, forKey: .lastEditor)
        lastEditorDisplayName = try container.decodeIfPresent(String.self, forKey: .lastEditorDisplayName)

        // Decoding into a `TimeInterval` rather than an integer avoids the trap an out of range value would cause on the platforms where `Int` is only 32 bits wide.
        let secondsSince1970 = try container.decode(TimeInterval.self, forKey: .modification)
        modification = Date(timeIntervalSince1970: secondsSince1970)
    }

    // MARK: - Encodable

    ///
    /// The keys a page is encoded under, which are the property names rather than the names the server sends.
    ///
    /// Encoding deliberately does not reuse ``CodingKeys``: those exist to read the server's payload and carry its naming, which would leak back out into anything this library encodes. Keeping the two apart is what makes the encoded form match the model a Swift caller sees, including where a property was renamed for clarity such as ``modification`` over the server's `timestamp`.
    ///
    /// ``isLandingPage`` is encoded as well although the server does not send it, because it is part of the model a caller sees and reproducing the comparison it stands for is exactly what encoding is meant to spare them.
    ///
    private enum EncodingKeys: String, CodingKey {
        case id
        case title
        case slug
        case emoji
        case fileName
        case filePath
        case collectivePath
        case parentId
        case isLandingPage
        case modification
        case size
        case isFullWidth
        case tags
        case subpageOrder
        case linkedPageIds
        case lastEditor
        case lastEditorDisplayName
    }

    ///
    /// Encode a page under its property names, so that the encoded form mirrors this type rather than the server's payload.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(slug, forKey: .slug)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(collectivePath, forKey: .collectivePath)
        try container.encode(parentId, forKey: .parentId)
        try container.encode(isLandingPage, forKey: .isLandingPage)
        try container.encode(modification, forKey: .modification)
        try container.encode(size, forKey: .size)
        try container.encode(isFullWidth, forKey: .isFullWidth)
        try container.encode(tags, forKey: .tags)
        try container.encode(subpageOrder, forKey: .subpageOrder)
        try container.encode(linkedPageIds, forKey: .linkedPageIds)
        try container.encode(lastEditor, forKey: .lastEditor)
        try container.encode(lastEditorDisplayName, forKey: .lastEditorDisplayName)
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a page.
    ///
    public var description: String {
        title
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a page.
    ///
    public var debugDescription: String {
        "#\(id) (\(filePath.isEmpty ? "/" : filePath)/\(fileName)): \(title)"
    }
}
