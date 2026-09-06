// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The settings the notes app keeps for the authenticated user.
///
/// Retrieved through ``Server/notesSettings()``. These describe where and how the app stores notes, which a client needs to know because notes are ordinary files: ``notesPath`` is what makes them reachable over WebDAV, for example through ``Server/enumerate(at:recursively:)``, and ``fileSuffix`` is the extension the app gives a note it creates.
///
/// The app resolves both lazily and persists them the first time it is asked about notes, so asking the server is the only reliable way to learn them. ``Notes/notesPath`` advertises the same path alongside the capabilities, which spares a second request to a client which fetched those anyway.
///
public struct NotesSettings: Model, Decodable {
    ///
    /// The path of the folder the notes are stored in, relative to the account's files, e.g. `"Notes"`.
    ///
    /// This is not a fixed name. Its default is derived from the account's locale, so an account in German ends up with `"Notizen"` unless it was set to something else, and it can be changed by the user at any time.
    ///
    public let notesPath: String

    ///
    /// The file extension the app gives a note it creates, e.g. `".md"`.
    ///
    /// The app reads a note from any file it recognizes regardless of this, so it says what new notes will look like rather than what existing ones do.
    ///
    public let fileSuffix: String
}
