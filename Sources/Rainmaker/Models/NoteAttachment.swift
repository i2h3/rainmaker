// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A file a note refers to, such as an image embedded into it, as ``Server/attachment(at:ofNote:)`` retrieves it into memory.
///
/// Its counterpart for a file written to a local location instead is ``NoteAttachmentFile``, which ``Server/downloadAttachment(at:ofNote:to:force:)`` returns.
///
/// There is deliberately no file name. The server names one in its `Content-Disposition` header, but as raw UTF-8 bytes which Foundation reads as Latin-1, so any name beyond plain ASCII would arrive garbled. The last component of the path the attachment was retrieved by is the reliable name, because that path names the file.
///
public struct NoteAttachment: Model, Hashable {
    ///
    /// The bytes of the file exactly as the server sent them.
    ///
    public let data: Data

    ///
    /// The MIME type of ``data`` as the server states it, e.g. `"image/png"`.
    ///
    /// The server derives it from the extension of the file name rather than from the bytes, and it reports types a browser would render as a document, which are SVG and HTML, as `"text/plain"`, so that opening an attachment cannot run anything. A type it does not know is `"application/octet-stream"`, which is also what a response without a type is taken to be.
    ///
    public let contentType: String

    ///
    /// Create an attachment from its bytes and their type, for example to fake the result of ``Server/attachment(at:ofNote:)``.
    ///
    /// - Parameters:
    ///     - data: The bytes of the file.
    ///     - contentType: The MIME type of the bytes.
    ///
    public init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }
}
