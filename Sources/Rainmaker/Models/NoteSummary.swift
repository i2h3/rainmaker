// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single note of the authenticated user on the server, described by everything but its text.
///
/// This is what the listings which leave out the content of the notes report, ``Server/noteSummaries(changedSince:)`` and its conditional and chunked counterparts, as the ``NoteSummaryChanges/changed`` notes of a ``NoteSummaryChanges``.
/// They ask the server not to send the text of any note, so a client which does not need it, such as one which only shows titles or which deliberately keeps no copy of a note's text, never downloads it. Retrieve a single note in full through ``Server/note(_:)`` when its text is needed after all.
/// Every property means exactly what the property of the same name of ``Note`` means, and the server sends the same values for both, including the ``entityTag``, with the one exception of ``isReadOnly`` explained below.
///
/// A summary deliberately has no counterpart to ``Note/hasError`` and ``Note/errorType``. The server only notices that it cannot read a note while reading its text, which a summary listing asks it to skip, so it then always reports that there was no error. A property which could only ever say so would claim that every note was readable. For the same reason ``isReadOnly`` is not forced for a note the server could not read, as it is for a ``Note``, but reflects the permissions on the note's file alone.
///
/// A summary is usually decoded from a server's response, but ``init(id:entityTag:isReadOnly:title:category:isFavorite:modification:path:isShared:shareTypes:)`` creates one from its individual values, for example to stand in for a server's response in the tests of a downstream project.
///
public struct NoteSummary: Model, Hashable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the note, unique per account, which is the same as ``Note/id``.
    ///
    public let id: Int

    ///
    /// The entity tag of the note, which changes if and only if the note changes on the server, its text included.
    ///
    /// This corresponds to the server's `etag` field and is the very ``Note/entityTag`` a ``Note`` of the same note carries, because the server derives it from the note's values and a digest of its text it keeps, whether or not the text is sent.
    /// It can therefore be passed to ``Server/note(_:ifChangedFrom:)`` to retrieve the note in full only when it is not the one at hand, and to ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` to change it only while the server still has it as summarized.
    ///
    public let entityTag: String

    ///
    /// Whether the note cannot be edited, for example because it was shared by another user without granting write access.
    ///
    /// This corresponds to the server's `readonly` field. Unlike ``Note/isReadOnly`` it is never forced by a failure to read the note, because a summary listing does not read the note's text.
    ///
    public let isReadOnly: Bool

    ///
    /// The title of the note, which the server also uses as the file name of the note's file, see ``Note/title``.
    ///
    public let title: String

    ///
    /// The category the note is filed under, which the server maps to a folder inside the notes folder, see ``Note/category``.
    ///
    /// This is an empty string rather than `nil` when the note is uncategorized, matching what the server sends.
    ///
    public let category: String

    ///
    /// Whether the note is marked as a favorite, which clients customarily surface at the top of a list.
    ///
    public let isFavorite: Bool

    ///
    /// The moment the note was last modified, see ``Note/modification``.
    ///
    /// This corresponds to the server's `modified` field, a number of whole seconds since the Unix epoch, and must never be passed to ``Server/noteSummaries(changedSince:)`` for the reasons ``Note/modification`` gives.
    ///
    public let modification: Date

    ///
    /// The path of the note's file relative to the account's files, with a leading slash, see ``Note/path``.
    ///
    /// Every release of the notes app serving ``Notes/minimumAPIVersion`` sends it, so this is `nil` only for a summary created without it through the memberwise initializer or decoded from a payload written by hand.
    ///
    public let path: String?

    ///
    /// Whether the note's file is shared with anyone, which is the case exactly when ``shareTypes`` is not empty, see ``Note/isShared``.
    ///
    public let isShared: Bool

    ///
    /// The kinds of share the note's file is part of, one entry per kind, which is empty when ``isShared`` is `false`, see ``Note/shareTypes``.
    ///
    public let shareTypes: [ShareType]

    ///
    /// Create a summary from its individual values, for example to stand in for a server's response in the tests of a downstream project.
    ///
    /// The defaults are what the server sends for an ordinary, uncategorized note which is neither a favorite nor shared.
    ///
    /// - Parameters:
    ///     - id: The server-assigned identifier, see ``id``.
    ///     - entityTag: The entity tag, see ``entityTag``.
    ///     - isReadOnly: Whether the note cannot be edited, see ``isReadOnly``. Defaults to `false`.
    ///     - title: The title, see ``title``.
    ///     - category: The category, see ``category``. Defaults to an empty string, meaning uncategorized.
    ///     - isFavorite: Whether the note is a favorite, see ``isFavorite``. Defaults to `false`.
    ///     - modification: The moment of the last modification, see ``modification``.
    ///     - path: The path of the note's file, see ``path``. Defaults to `nil`.
    ///     - isShared: Whether the note's file is shared, see ``isShared``. Defaults to `false`.
    ///     - shareTypes: The kinds of share the note's file is part of, see ``shareTypes``. Defaults to none.
    ///
    public init(id: Int, entityTag: String, isReadOnly: Bool = false, title: String, category: String = "", isFavorite: Bool = false, modification: Date, path: String? = nil, isShared: Bool = false, shareTypes: [ShareType] = []) {
        self.id = id
        self.entityTag = entityTag
        self.isReadOnly = isReadOnly
        self.title = title
        self.category = category
        self.isFavorite = isFavorite
        self.modification = modification
        self.path = path
        self.isShared = isShared
        self.shareTypes = shareTypes
    }

    ///
    /// The keys a summary is decoded from, which are the names the server sends and the same as those ``Note`` is decoded from, but for the content and the error the server sends for a note without its text.
    ///
    private enum CodingKeys: String, CodingKey {
        case id
        case entityTag = "etag"
        case isReadOnly = "readonly"
        case title
        case category
        case isFavorite = "favorite"
        case modification = "modified"
        case path = "internalPath"
        case isShared
        case shareTypes
    }

    // MARK: - Decodable

    ///
    /// Decode a summary from the server's payload.
    ///
    /// The same fields as for ``Note/init(from:)`` are required, but for `content`, `error` and `errorType`, which are not read even when present: the server sends no content for a note a summary listing asks about, and only ever reports that there was no error then. ``path``, ``isShared`` and ``shareTypes`` are decoded only if present, falling back to `nil`, `false` and no share types, as with ``Note``.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        entityTag = try container.decode(String.self, forKey: .entityTag)
        isReadOnly = try container.decode(Bool.self, forKey: .isReadOnly)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)

        // Decoding into a `TimeInterval` rather than an integer avoids the trap an out of range value would cause on the platforms where `Int` is only 32 bits wide.
        let secondsSince1970 = try container.decode(TimeInterval.self, forKey: .modification)
        modification = Date(timeIntervalSince1970: secondsSince1970)

        path = try container.decodeIfPresent(String.self, forKey: .path)
        isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        shareTypes = try container.decodeIfPresent([ShareType].self, forKey: .shareTypes) ?? []
    }

    // MARK: - Encodable

    ///
    /// The keys a summary is encoded under, which are the property names rather than the names the server sends, as with ``Note``.
    ///
    private enum EncodingKeys: String, CodingKey {
        case id
        case entityTag
        case isReadOnly
        case title
        case category
        case isFavorite
        case modification
        case path
        case isShared
        case shareTypes
    }

    ///
    /// Encode a summary under its property names, so that the encoded form mirrors this type rather than the server's payload.
    ///
    /// Like ``Note`` it encodes an absent ``path`` as `null`, so that the encoded form always has the same keys.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(entityTag, forKey: .entityTag)
        try container.encode(isReadOnly, forKey: .isReadOnly)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(modification, forKey: .modification)
        try container.encode(path, forKey: .path)
        try container.encode(isShared, forKey: .isShared)
        try container.encode(shareTypes, forKey: .shareTypes)
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a summary, which is the note's title as for ``Note``.
    ///
    public var description: String {
        title
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a summary, in the same form as for ``Note``.
    ///
    public var debugDescription: String {
        "#\(id) (\(category.isEmpty ? "uncategorized" : category)): \(title)"
    }
}
