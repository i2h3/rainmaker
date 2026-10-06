// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The JSON body ``Server/createNote(title:category:content:modification:isFavorite:)`` sends to `POST /index.php/apps/notes/api/v1/notes`.
///
/// This is a data transfer object shaped as the notes app expects it, which is why its properties carry the server's names rather than those of ``Note``. It is the request counterpart of the data transfer objects in `Responses/Models` and is not exposed outside this module.
///
/// The synthesized encoding leaves out ``modified`` when it is `nil`, which the server takes as a request to keep the moment it created the note's file at.
///
struct NoteCreationRequest: Encodable {
    ///
    /// The requested title, which the server sanitizes before it becomes the file name and therefore ``Note/title``.
    ///
    let title: String

    ///
    /// The requested category, which the server sanitizes before it becomes the folder the note is filed in and therefore ``Note/category``.
    ///
    let category: String

    ///
    /// The text of the new note, which becomes ``Note/content``.
    ///
    let content: String

    ///
    /// The modification moment to stamp onto the new note's file, in whole seconds since the Unix epoch as `Date.wholeSecondsSince1970` converts it, which becomes ``Note/modification``.
    ///
    let modified: Int64?

    ///
    /// Whether the new note is marked as a favorite, which becomes ``Note/isFavorite``.
    ///
    let favorite: Bool
}
