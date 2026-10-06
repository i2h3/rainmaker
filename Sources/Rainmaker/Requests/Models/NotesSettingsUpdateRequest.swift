// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The JSON body ``Server/updateNotesSettings(notesPath:fileSuffix:noteMode:showsHiddenFiles:loadsRecentNoteOnStartUp:)`` sends to `PUT /index.php/apps/notes/api/v1/settings`.
///
/// This is a data transfer object shaped as the notes app expects it, which is why its properties carry the server's names rather than those of ``NotesSettings``. It is the request counterpart of the data transfer objects in `Responses/Models` and is not exposed outside this module.
///
/// Every property is optional, and the synthesized encoding leaves out those which are `nil`, because the server keeps every setting the body does not name, while a setting sent as `null` is reset to its default.
///
struct NotesSettingsUpdateRequest: Encodable {
    ///
    /// The new path of the folder the notes are stored in, relative to the account's files, or `nil` to keep ``NotesSettings/notesPath``.
    ///
    let notesPath: String?

    ///
    /// The new file extension for notes created from now on, or `nil` to keep ``NotesSettings/fileSuffix``.
    ///
    let fileSuffix: String?

    ///
    /// The raw value of the new ``NoteMode``, which is the string the server expects, or `nil` to keep ``NotesSettings/noteMode``.
    ///
    let noteMode: String?

    ///
    /// Whether the web interface is to list hidden files and folders, or `nil` to keep ``NotesSettings/showsHiddenFiles``.
    ///
    let showHidden: Bool?

    ///
    /// Whether the web interface is to open the most recent note when it starts, or `nil` to keep ``NotesSettings/loadsRecentNoteOnStartUp``.
    ///
    let loadRecentOnStartUp: Bool?
}
