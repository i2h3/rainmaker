// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single note of the authenticated user on the server.
///
/// Notes are listed through ``Server/notes()`` and, incrementally, through ``Server/notes(changedSince:)``. Whether the notes app which provides them is available at all can be checked in advance via the ``Notes`` capability, e.g. `try await capabilities().contains(Notes.self)`.
///
/// Every note is a file in the account's notes folder, which is why ``title`` doubles as its file name and ``category`` as the folder it sits in.
/// The attachments ``content`` may refer to are intentionally not modelled, as retrieving them is out of scope.
///
public struct Note: Model, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the note, unique per account.
    ///
    public let id: Int

    ///
    /// The entity tag of the note, which changes if and only if the note changes on the server.
    ///
    /// This corresponds to the server's `etag` field and is what a client compares against to learn whether its local copy is stale.
    ///
    public let entityTag: String

    ///
    /// Whether the note cannot be edited, for example because it was shared by another user without granting write access.
    ///
    /// This corresponds to the server's `readonly` field.
    ///
    public let isReadOnly: Bool

    ///
    /// The title of the note, which the server also uses as the file name of the note's file.
    ///
    /// The server sanitizes titles, so this is not necessarily what a client requested when it last wrote the note.
    ///
    public let title: String

    ///
    /// The category the note is filed under, which the server maps to a folder inside the notes folder.
    ///
    /// This is an empty string rather than `nil` when the note is uncategorized, matching what the server sends.
    /// Sub-categories are delimited by `/`, e.g. `"Work/Meetings"`.
    ///
    public let category: String

    ///
    /// The text of the note, which the notes app formats as Markdown.
    ///
    public let content: String

    ///
    /// Whether the note is marked as a favorite, which clients customarily surface at the top of a list.
    ///
    public let isFavorite: Bool

    ///
    /// The moment the note was last modified.
    ///
    /// This corresponds to the server's `modified` field, a number of whole seconds since the Unix epoch.
    /// The conversion happens in ``init(from:)`` rather than through a decoder's date strategy, so that this type decodes correctly no matter which `JSONDecoder` a downstream project passes it to.
    ///
    /// This is the date of the note itself and not the moment the server noticed it, which is why it must never be passed to ``Server/notes(changedSince:)``: a note may be from 2020, but when the server only found it today it is not pruned from that call's response.
    ///
    public let modification: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case entityTag = "etag"
        case isReadOnly = "readonly"
        case title
        case category
        case content
        case isFavorite = "favorite"
        case modification = "modified"
    }

    // MARK: - Decodable

    ///
    /// Decode a note from the server's payload.
    ///
    /// Every field is required. ``Notes/minimumAPIVersion`` is enforced before a payload reaches this type, and that version sends all of them, so a missing field means a response this type cannot describe rather than an older server. The notes this library requests are also never reduced by an `exclude` parameter, and the reduced form a `pruneBefore` request produces is recognized before decoding is attempted.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        entityTag = try container.decode(String.self, forKey: .entityTag)
        isReadOnly = try container.decode(Bool.self, forKey: .isReadOnly)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        content = try container.decode(String.self, forKey: .content)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)

        // Decoding into a `TimeInterval` rather than an integer avoids the trap an out of range value would cause on the platforms where `Int` is only 32 bits wide.
        let secondsSince1970 = try container.decode(TimeInterval.self, forKey: .modification)
        modification = Date(timeIntervalSince1970: secondsSince1970)
    }

    // MARK: - Encodable

    ///
    /// The keys a note is encoded under, which are the property names rather than the names the server sends.
    ///
    /// Encoding deliberately does not reuse ``CodingKeys``: those exist to read the server's payload and carry its naming, which would leak back out into anything this library encodes. Keeping the two apart is what makes the encoded form match the model a Swift caller sees, including where a property was renamed for clarity such as ``modification`` over the server's `modified`.
    ///
    private enum EncodingKeys: String, CodingKey {
        case id
        case entityTag
        case isReadOnly
        case title
        case category
        case content
        case isFavorite
        case modification
    }

    ///
    /// Encode a note under its property names, so that the encoded form mirrors this type rather than the server's payload.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(entityTag, forKey: .entityTag)
        try container.encode(isReadOnly, forKey: .isReadOnly)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(content, forKey: .content)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(modification, forKey: .modification)
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a note.
    ///
    public var description: String {
        title
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a note.
    ///
    public var debugDescription: String {
        "#\(id) (\(category.isEmpty ? "uncategorized" : category)): \(title)"
    }
}
