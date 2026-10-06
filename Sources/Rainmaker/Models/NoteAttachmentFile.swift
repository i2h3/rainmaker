// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A file a note refers to, such as an image embedded into it, as ``Server/downloadAttachment(at:ofNote:to:force:)`` wrote it to a local location.
///
/// This is the counterpart of ``NoteAttachment`` for a file which is not held in memory but streamed to disk, which suits large files and a process with little memory to spare, such as an extension. As there, the last component of the path the attachment was retrieved by is its reliable name rather than anything the server says about it.
///
public struct NoteAttachmentFile: Model, Hashable {
    ///
    /// The local location the file was written to, which is the destination ``Server/downloadAttachment(at:ofNote:to:force:)`` was given.
    ///
    public let location: URL

    ///
    /// The MIME type of the file as the server states it, e.g. `"image/png"`, with the same caveats as ``NoteAttachment/contentType``.
    ///
    public let contentType: String

    ///
    /// Create a downloaded attachment from its location and its type, for example to fake the result of ``Server/downloadAttachment(at:ofNote:to:force:)``.
    ///
    /// - Parameters:
    ///     - location: The local location of the file.
    ///     - contentType: The MIME type of the file.
    ///
    public init(location: URL, contentType: String) {
        self.location = location
        self.contentType = contentType
    }
}
