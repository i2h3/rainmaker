// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single note of the authenticated user on the server.
///
/// Notes are listed through ``Server/notes()`` and, incrementally, through ``Server/notes(changedSince:)``, while a single one is retrieved by its ``id`` through ``Server/note(_:)``.
/// A client which does not need the text of the notes lists them as ``NoteSummary`` values through ``Server/noteSummaries(changedSince:)`` instead, which carry everything but the text and the error a failure to read it would cause.
/// Notes are created through ``Server/createNote(title:category:content:modification:isFavorite:)``, changed through ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` and deleted through ``Server/deleteNote(_:)``. Whether the notes app which provides them is available at all can be checked in advance via the ``Notes`` capability, e.g. `try await capabilities().contains(Notes.self)`.
///
/// Every note is a file in the account's notes folder, which is why ``title`` doubles as its file name and ``category`` as the folder it sits in.
/// Where exactly that file is, is what ``path`` says, and whether it is shared with anyone is what ``isShared`` and ``shareTypes`` say.
///
/// A note is usually decoded from a server's response, but ``init(id:entityTag:isReadOnly:title:category:content:hasError:errorType:isFavorite:modification:path:isShared:shareTypes:)`` creates one from its individual values, for example to stand in for a server's response in the tests of a downstream project.
///
/// A note the server could not read is still listed rather than omitted, and the response still succeeds. Such a note carries ``hasError``, and its ``content`` is a message about the failure instead of the note's text. Anything which stores what it retrieves has to check that before writing, or it replaces a perfectly good local copy with an error message.
///
public struct Note: Model, Hashable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the note, unique per account.
    ///
    public let id: Int

    ///
    /// The entity tag of the note, which changes if and only if the note changes on the server.
    ///
    /// This corresponds to the server's `etag` field and is what a client compares against to learn whether its local copy is stale.
    /// ``Server/note(_:ifChangedFrom:)`` takes it to have the server make that comparison and skip the transfer of a note which did not change.
    /// ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` takes it to change the note only while the server still has that very copy.
    ///
    public let entityTag: String

    ///
    /// Whether the note cannot be edited, for example because it was shared by another user without granting write access.
    ///
    /// This corresponds to the server's `readonly` field.
    /// The server also forces it for a note it could not read, so on its own it is not a statement about permissions; see ``hasError``.
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
    /// This is only the note's text while ``hasError`` is `false`. For a note the server could not read it is the message the server substituted for it, which is localized to the account's language and names the failure, for example `"Error: OCP\\Files\\NotPermittedException"`.
    ///
    public let content: String

    ///
    /// Whether the server ran into an error while reading this note.
    ///
    /// The note is listed all the same and the response still succeeds, so this is the only reliable way to tell a note which was read from one which was not. When it is `true` the server has replaced ``content`` with a message about the failure, named the failure in ``errorType``, and forced ``isReadOnly``.
    ///
    /// This corresponds to the server's `error` field, which every server serving version 1 of the API sends.
    ///
    public let hasError: Bool

    ///
    /// The kind of error the server ran into while reading this note, as the class name it uses internally, for example `"OCP\\Files\\NotPermittedException"`.
    ///
    /// Empty whenever ``hasError`` is `false`. It is meant for telling failures apart and for reporting them, not for display: it is an implementation detail of the server rather than anything a user would recognize.
    ///
    public let errorType: String

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

    ///
    /// The path of the note's file relative to the account's files, with a leading slash, e.g. `"/Notes/Recipes/Pancakes.md"`.
    ///
    /// This corresponds to the server's `internalPath` field and is what makes the note's file reachable over WebDAV, for example through ``Server/info(_:)`` or ``Server/download(_:to:force:)``.
    /// It starts with ``NotesSettings/notesPath`` and continues with ``category`` and the file name derived from ``title``, but asking for it rather than assembling it is the only reliable way, because the server sanitizes both and picks the file extension.
    /// The attachments of a note are files as well: releases of the notes app from 6.1.0 on, see ``Notes/storesAttachmentsPerNote``, keep those uploaded through the notes API in a hidden `.attachments.<id>` folder in the same folder as this file, where `<id>` is ``id``.
    ///
    /// Every release of the notes app serving ``Notes/minimumAPIVersion`` sends it, so this is `nil` only for a note created without it through the memberwise initializer or decoded from a payload written by hand.
    ///
    public let path: String?

    ///
    /// Whether the note's file is shared with anyone, which is the case exactly when ``shareTypes`` is not empty.
    ///
    /// This corresponds to the server's `isShared` field. It reports the shares the owner of the note's file created for it, which is the authenticated user for every note in their own notes folder.
    ///
    public let isShared: Bool

    ///
    /// The kinds of share the note's file is part of, one entry per kind, which is empty when ``isShared`` is `false`.
    ///
    /// This corresponds to the server's `shareTypes` field. The server only looks for the kinds ``ShareType`` has named constants for, but any other number it might send in future is kept rather than dropped.
    ///
    public let shareTypes: [ShareType]

    ///
    /// Create a note from its individual values, for example to stand in for a server's response in the tests of a downstream project.
    ///
    /// The defaults are what the server sends for an ordinary, uncategorized note it read without trouble and which is neither a favorite nor shared.
    ///
    /// - Parameters:
    ///     - id: The server-assigned identifier, see ``id``.
    ///     - entityTag: The entity tag, see ``entityTag``.
    ///     - isReadOnly: Whether the note cannot be edited, see ``isReadOnly``. Defaults to `false`.
    ///     - title: The title, see ``title``.
    ///     - category: The category, see ``category``. Defaults to an empty string, meaning uncategorized.
    ///     - content: The text, see ``content``.
    ///     - hasError: Whether the server could not read the note, see ``hasError``. Defaults to `false`.
    ///     - errorType: The kind of error, see ``errorType``. Defaults to an empty string.
    ///     - isFavorite: Whether the note is a favorite, see ``isFavorite``. Defaults to `false`.
    ///     - modification: The moment of the last modification, see ``modification``.
    ///     - path: The path of the note's file, see ``path``. Defaults to `nil`.
    ///     - isShared: Whether the note's file is shared, see ``isShared``. Defaults to `false`.
    ///     - shareTypes: The kinds of share the note's file is part of, see ``shareTypes``. Defaults to none.
    ///
    public init(id: Int, entityTag: String, isReadOnly: Bool = false, title: String, category: String = "", content: String, hasError: Bool = false, errorType: String = "", isFavorite: Bool = false, modification: Date, path: String? = nil, isShared: Bool = false, shareTypes: [ShareType] = []) {
        self.id = id
        self.entityTag = entityTag
        self.isReadOnly = isReadOnly
        self.title = title
        self.category = category
        self.content = content
        self.hasError = hasError
        self.errorType = errorType
        self.isFavorite = isFavorite
        self.modification = modification
        self.path = path
        self.isShared = isShared
        self.shareTypes = shareTypes
    }

    ///
    /// The keys a note is decoded from, which are the names the server sends. Encoding uses the separate encoding keys below so that the server's naming does not leak into the encoded form.
    ///
    private enum CodingKeys: String, CodingKey {
        case id
        case entityTag = "etag"
        case isReadOnly = "readonly"
        case title
        case category
        case content
        case hasError = "error"
        case errorType
        case isFavorite = "favorite"
        case modification = "modified"
        case path = "internalPath"
        case isShared
        case shareTypes
    }

    // MARK: - Decodable

    ///
    /// Decode a note from the server's payload.
    ///
    /// Every field but ``path``, ``isShared`` and ``shareTypes`` is required, ``hasError`` and ``errorType`` included: the server has sent those since it first served version 1 of the API. ``Notes/minimumAPIVersion`` is enforced before a payload reaches this type, and that version sends all of them, so a missing field means a response this type cannot describe rather than an older server. The notes this library decodes as a note are also never reduced by an `exclude` parameter, because the listings which leave out the content decode ``NoteSummary`` instead, and the reduced form a `pruneBefore` request produces is recognized before decoding is attempted.
    ///
    /// The server sends ``path``, ``isShared`` and ``shareTypes`` as well, since long before ``Notes/minimumAPIVersion``. They are decoded only if present all the same, falling back to `nil`, `false` and no share types, so that a payload written by hand, for example in the tests of a downstream project, does not have to carry them.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        entityTag = try container.decode(String.self, forKey: .entityTag)
        isReadOnly = try container.decode(Bool.self, forKey: .isReadOnly)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        content = try container.decode(String.self, forKey: .content)
        hasError = try container.decode(Bool.self, forKey: .hasError)
        errorType = try container.decode(String.self, forKey: .errorType)
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
    /// The keys a note is encoded under, which are the property names rather than the names the server sends.
    ///
    /// Encoding deliberately does not reuse ``CodingKeys``: those exist to read the server's payload and carry its naming, which would leak back out into anything this library encodes. Keeping the two apart is what makes the encoded form match the model a Swift caller sees, including where a property was renamed for clarity such as ``modification`` over the server's `modified` or ``path`` over its `internalPath`.
    ///
    private enum EncodingKeys: String, CodingKey {
        case id
        case entityTag
        case isReadOnly
        case title
        case category
        case content
        case hasError
        case errorType
        case isFavorite
        case modification
        case path
        case isShared
        case shareTypes
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
        try container.encode(hasError, forKey: .hasError)
        try container.encode(errorType, forKey: .errorType)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(modification, forKey: .modification)
        try container.encode(path, forKey: .path)
        try container.encode(isShared, forKey: .isShared)
        try container.encode(shareTypes, forKey: .shareTypes)
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
