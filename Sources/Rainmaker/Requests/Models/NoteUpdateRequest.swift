// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The JSON body ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` sends to `PUT /index.php/apps/notes/api/v1/notes/<id>`.
///
/// This is a data transfer object shaped as the notes app expects it, which is why its properties carry the server's names rather than those of ``Note``. It is the request counterpart of the data transfer objects in `Responses/Models` and is not exposed outside this module.
///
/// Every property is optional, and the synthesized encoding leaves out those which are `nil`, because the server only changes what the body names and leaves everything else of the note as it is.
///
struct NoteUpdateRequest: Encodable {
    ///
    /// The new title, which the server sanitizes before it renames the note's file, or `nil` to keep ``Note/title``.
    ///
    let title: String?

    ///
    /// The new category, which the server sanitizes before it moves the note's file into the matching folder, or `nil` to keep ``Note/category``.
    ///
    let category: String?

    ///
    /// The new text of the note, or `nil` to keep ``Note/content``.
    ///
    let content: String?

    ///
    /// The modification moment to stamp onto the note's file, in whole seconds since the Unix epoch as `Date.wholeSecondsSince1970` converts it, or `nil` to leave ``Note/modification`` to the server.
    ///
    let modified: Int64?

    ///
    /// Whether the note is to be marked as a favorite, or `nil` to keep ``Note/isFavorite``.
    ///
    let favorite: Bool?
}
