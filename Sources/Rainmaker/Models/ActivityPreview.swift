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
public struct ActivityPreview: Model, Hashable, Decodable, CustomStringConvertible, CustomDebugStringConvertible {
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
    public let fileName: String

    ///
    /// The full path of the previewed file including the owning account, e.g. `"/admin/files/Readme.md"`. `nil` when the server does not report it.
    ///
    public let filePath: String?

    ///
    /// The keys a preview is decoded from, which are the names the server sends.
    ///
    private enum CodingKeys: String, CodingKey {
        case source
        case link
        case mimeType
        case isMimeTypeIcon
        case fileId
        case view
        case fileName = "filename"
        case filePath
    }

    // MARK: - Encodable

    ///
    /// The keys a preview is encoded under, which are the property names rather than the names the server sends.
    ///
    /// Encoding deliberately does not reuse ``CodingKeys``: those exist to read the server's payload and carry its naming, which would leak back out into anything this library encodes. Keeping the two apart is what makes the encoded form match the model a Swift caller sees, including where a property was renamed for clarity such as ``fileName`` over the server's `filename`.
    ///
    private enum EncodingKeys: String, CodingKey {
        case source
        case link
        case mimeType
        case isMimeTypeIcon
        case fileId
        case view
        case fileName
        case filePath
    }

    ///
    /// Encode a preview under its property names, so that the encoded form mirrors this type rather than the server's payload.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(source, forKey: .source)
        try container.encode(link, forKey: .link)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(isMimeTypeIcon, forKey: .isMimeTypeIcon)
        try container.encode(fileId, forKey: .fileId)
        try container.encode(view, forKey: .view)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(filePath, forKey: .filePath)
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a preview.
    ///
    public var description: String {
        fileName
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a preview.
    ///
    public var debugDescription: String {
        "#\(fileId) (\(mimeType)): \(fileName)"
    }
}
