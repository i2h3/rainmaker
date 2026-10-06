// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The way the notes app's web interface presents a note when it is opened.
///
/// This is the ``NotesSettings/noteMode`` of an account as retrieved through ``Server/notesSettings()``. It is a preference of the web interface only: the notes API serves the same Markdown in ``Note/content`` whatever it says, so a client may honor it to feel familiar but does not have to.
///
/// The raw values are the strings the server sends. A value this library does not know about does not decode as a case but leaves ``NotesSettings/noteMode`` `nil`, which is why this enum needs no catch-all case.
///
public enum NoteMode: String, Model, Hashable, CaseIterable {
    ///
    /// Notes open in the rich text editor of the Nextcloud Text app, equalling the raw representation as `"rich"`.
    ///
    /// The notes app offers this mode only when the Text app is enabled, and then it is also the default.
    ///
    case rich

    ///
    /// Notes open in the notes app's own plain Markdown editor, equalling the raw representation as `"edit"`.
    ///
    /// This is the default when the Text app is not enabled.
    ///
    case edit

    ///
    /// Notes open as rendered Markdown which is not editable until the user switches to editing, equalling the raw representation as `"preview"`.
    ///
    case preview
}
