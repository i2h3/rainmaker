// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A thumbnail the server offers for a file an activity refers to.
///
/// Previews are not part of an activity by default. They are only included when they are requested through the `previews` parameter of ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)``, and only for activities which actually reference files. Whether the server supports them at all is advertised under the ``Activity`` capability's `"previews"` entry.
///
/// A single activity can carry several previews because activities about multiple files are merged into one entry by the server.
///
public struct ActivityPreview: Model, Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    ///
    /// The address of the image to display.
    ///
    /// Depending on ``isMimeTypeIcon`` this is either a rendered thumbnail of the file's content or a generic icon standing in for its media type.
    ///
    public let source: String

    ///
    /// The address to open when the preview is activated, pointing at the file itself rather than at its image.
    ///
    public let link: String

    ///
    /// The media type of the previewed file, e.g. `"text/markdown"`.
    ///
    public let mimeType: String

    ///
    /// Whether ``source`` is a generic media type icon instead of a rendered thumbnail of the file.
    ///
    /// The server falls back to an icon when it cannot render a thumbnail, for example for plain text documents.
    ///
    public let isMimeTypeIcon: Bool

    ///
    /// The identifier of the previewed file on the server.
    ///
    public let fileId: Int

    ///
    /// The app the file is viewed in, e.g. `"files"` or `"trashbin"`.
    ///
    public let view: String

    ///
    /// The name of the previewed file.
    ///
    public let filename: String

    ///
    /// The full path of the previewed file including the owning account, e.g. `"/admin/files/Readme.md"`. `nil` when the server does not report it.
    ///
    public let filePath: String?

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a preview.
    ///
    public var description: String {
        filename
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a preview.
    ///
    public var debugDescription: String {
        "#\(fileId) (\(mimeType)): \(filename)"
    }
}
