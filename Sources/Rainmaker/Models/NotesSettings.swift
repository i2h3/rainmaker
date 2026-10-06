// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The settings the notes app keeps for the authenticated user.
///
/// Retrieved through ``Server/notesSettings()``. These describe where and how the app stores notes, which a client needs to know because notes are ordinary files: ``notesPath`` is what makes them reachable over WebDAV, for example through ``Server/enumerate(at:recursively:)->[Item]``, and ``fileSuffix`` is the extension the app gives a note it creates.
///
/// The app resolves both lazily and persists them the first time it is asked about notes, so asking the server is the only reliable way to learn them. ``Notes/notesPath`` advertises the same path alongside the capabilities, which spares a second request to a client which fetched those anyway.
///
/// The remaining settings are preferences of the app's web interface which a client may honor to feel familiar. Each of them is optional, because older releases of the notes app do not send all of them.
///
public struct NotesSettings: Model, Hashable, Decodable {
    ///
    /// The path of the folder the notes are stored in, relative to the account's files, e.g. `"Notes"`.
    ///
    /// This is not a fixed name. Its default is derived from the account's locale, so an account in German ends up with `"Notizen"` unless it was set to something else, and it can be changed by the user at any time.
    ///
    public let notesPath: String

    ///
    /// The file extension the app gives a note it creates, e.g. `".md"`, which is also the default.
    ///
    /// The app reads a note from any file it recognizes regardless of this, so it says what new notes will look like rather than what existing ones do.
    ///
    public let fileSuffix: String

    ///
    /// The way the app's web interface presents a note when it is opened, which corresponds to the server's `noteMode` field.
    ///
    /// This is `nil` when the server does not send the field or sends a value ``NoteMode`` has no case for, so that a mode introduced by a future release of the notes app cannot fail the lookup of the settings as a whole.
    ///
    public let noteMode: NoteMode?

    ///
    /// Whether the app's web interface lists files and folders whose names start with a dot, which corresponds to the server's `showHidden` field.
    ///
    /// The notes app sends this since release 6.1.0, so it is `nil` for older releases.
    ///
    public let showsHiddenFiles: Bool?

    ///
    /// Whether the app's web interface opens the most recently edited note when it starts, which corresponds to the server's `loadRecentOnStartUp` field.
    ///
    /// The notes app sends this since release 6.1.0, so it is `nil` for older releases.
    ///
    public let loadsRecentNoteOnStartUp: Bool?

    ///
    /// Create settings from their individual values, for example to stand in for a server's response in the tests of a downstream project.
    ///
    /// - Parameters:
    ///     - notesPath: The path of the folder the notes are stored in, see ``notesPath``.
    ///     - fileSuffix: The file extension the app gives a note it creates, see ``fileSuffix``.
    ///     - noteMode: The way the web interface presents a note, see ``noteMode``. Defaults to `nil`.
    ///     - showsHiddenFiles: Whether the web interface lists hidden files and folders, see ``showsHiddenFiles``. Defaults to `nil`.
    ///     - loadsRecentNoteOnStartUp: Whether the web interface opens the most recent note when it starts, see ``loadsRecentNoteOnStartUp``. Defaults to `nil`.
    ///
    public init(notesPath: String, fileSuffix: String, noteMode: NoteMode? = nil, showsHiddenFiles: Bool? = nil, loadsRecentNoteOnStartUp: Bool? = nil) {
        self.notesPath = notesPath
        self.fileSuffix = fileSuffix
        self.noteMode = noteMode
        self.showsHiddenFiles = showsHiddenFiles
        self.loadsRecentNoteOnStartUp = loadsRecentNoteOnStartUp
    }

    ///
    /// The keys settings are decoded from, which are the names the server sends. Encoding uses the separate encoding keys below so that the server's naming does not leak into the encoded form.
    ///
    private enum CodingKeys: String, CodingKey {
        case notesPath
        case fileSuffix
        case noteMode
        case showsHiddenFiles = "showHidden"
        case loadsRecentNoteOnStartUp = "loadRecentOnStartUp"
    }

    // MARK: - Decodable

    ///
    /// Decode settings from the server's payload.
    ///
    /// Only ``notesPath`` and ``fileSuffix`` are required, because every release of the notes app serving ``Notes/minimumAPIVersion`` sends them. The other fields are decoded if present, and ``noteMode`` is read as a plain string first so that a value ``NoteMode`` does not know about leaves it `nil` rather than failing.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        notesPath = try container.decode(String.self, forKey: .notesPath)
        fileSuffix = try container.decode(String.self, forKey: .fileSuffix)
        noteMode = try container.decodeIfPresent(String.self, forKey: .noteMode).flatMap(NoteMode.init(rawValue:))
        showsHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showsHiddenFiles)
        loadsRecentNoteOnStartUp = try container.decodeIfPresent(Bool.self, forKey: .loadsRecentNoteOnStartUp)
    }

    // MARK: - Encodable

    ///
    /// The keys settings are encoded under, which are the property names rather than the names the server sends.
    ///
    /// Encoding deliberately does not reuse ``CodingKeys``, for the same reason ``Note`` keeps its encoding keys apart: the server's `showHidden` and `loadRecentOnStartUp` would otherwise leak into the encoded form in place of ``showsHiddenFiles`` and ``loadsRecentNoteOnStartUp``.
    ///
    private enum EncodingKeys: String, CodingKey {
        case notesPath
        case fileSuffix
        case noteMode
        case showsHiddenFiles
        case loadsRecentNoteOnStartUp
    }

    ///
    /// Encode settings under their property names, so that the encoded form mirrors this type rather than the server's payload.
    ///
    /// Absent values are encoded as `null` rather than left out, so that the encoded form always has the same keys.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(notesPath, forKey: .notesPath)
        try container.encode(fileSuffix, forKey: .fileSuffix)
        try container.encode(noteMode, forKey: .noteMode)
        try container.encode(showsHiddenFiles, forKey: .showsHiddenFiles)
        try container.encode(loadsRecentNoteOnStartUp, forKey: .loadsRecentNoteOnStartUp)
    }
}
