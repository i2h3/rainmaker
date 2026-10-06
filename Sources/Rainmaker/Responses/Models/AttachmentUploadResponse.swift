// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The JSON object the notes app answers an uploaded attachment with, for `POST /index.php/apps/notes/api/v1.4/attachment/<id>`.
///
/// This is a data transfer object which ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` and its counterpart for `Data` reduce to the path it carries right after decoding.
///
struct AttachmentUploadResponse: Decodable {
    ///
    /// The path the server stored the attachment at, relative to the folder of the note's category, which is what ``Server/attachment(at:ofNote:)`` and ``Server/deleteAttachment(at:ofNote:)`` take.
    ///
    let filename: String
}
