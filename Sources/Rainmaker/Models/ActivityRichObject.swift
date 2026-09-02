// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single interpolatable object referenced by a placeholder in an ``ActivityRichText``.
///
/// Nextcloud calls these "rich objects". They are what turns the flat sentence in ``ActivityItem/subject`` into something a client can render interactively: instead of the file name being baked into the text, the text carries a `{file}` placeholder and this type carries the file's identifier, name and address so that the client can draw it as a link, an avatar or a tag.
///
/// The server defines a couple of dozen object ``type`` values (`file`, `user`, `calendar-event`, `systemtag`, `open-graph` and more), and every installed app may contribute further ones. Modelling them as an open string rather than an enumeration therefore keeps this forward compatible: an unknown type can always still be rendered by falling back to ``name``.
///
/// Only ``type``, ``id`` and ``name`` are guaranteed by the server. ``path`` and ``link`` are surfaced explicitly because they are the two optional fields clients need most often, and every remaining field of the concrete object type is preserved in ``other``.
///
/// Every field is exposed as a `String`, including conceptually numeric ones such as a file size, a modification time or an identifier. The server usually sends those as JSON strings, but not dependably: some payloads carry a numeric `id`, and an app contributing its own object type is free to send a number or a boolean for any field. Such values are converted rather than discarded, so a numeric identifier arrives here as its decimal digits.
///
public struct ActivityRichObject: Model, Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    ///
    /// The kind of object this is, e.g. `"file"`, `"user"` or `"systemtag"`.
    ///
    /// This determines which fields are present in ``other``. It is deliberately not an enumeration because apps contribute their own types.
    ///
    public let type: String

    ///
    /// The identifier of the object within its type, e.g. a file identifier or a user name.
    ///
    /// This is a string even when the underlying identifier is numeric.
    ///
    public let id: String

    ///
    /// The human-readable name of the object, e.g. a file name or a user's display name.
    ///
    /// This is what a placeholder collapses to when an ``ActivityRichText`` is flattened through ``ActivityRichText/resolved()``.
    ///
    public let name: String

    ///
    /// The path of the object for the user, without a leading slash. `nil` when the object type has no path.
    ///
    public let path: String?

    ///
    /// The address to open when the object is activated. `nil` when the object carries no link.
    ///
    /// This is kept as a string rather than a `URL` for the same reason ``ActivityItem/link`` is: the server may return an empty value.
    ///
    public let link: String?

    ///
    /// Every remaining field the server sent for this object, keyed by its name as returned.
    ///
    /// For a `file` object this holds entries such as `"mimetype"`, `"size"`, `"mtime"`, `"etag"`, `"permissions"`, `"width"`, `"height"` or `"preview-available"`. Fields Rainmaker does not model explicitly stay accessible here instead of being dropped.
    ///
    public let other: [String: String]

    ///
    /// Coding keys for the fields surfaced as dedicated properties, used when encoding.
    ///
    /// Decoding does not go through these because every field of the server's object has to be read dynamically to populate ``other``.
    ///
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case path
        case link
        case other
    }

    ///
    /// A coding key which accepts any name, so that the object's fields can be enumerated without knowing them in advance.
    ///
    private struct DynamicKey: CodingKey {
        let stringValue: String

        var intValue: Int? {
            nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    // MARK: - Decodable

    ///
    /// Decode a rich object by reading every field the server sent, so that fields Rainmaker does not model are preserved in ``other`` instead of being lost.
    ///
    /// A field which is not a string is converted to one instead of being dropped, because the server does not dependably send numeric values such as an identifier as JSON strings and silently losing an identifier would be worse than reporting its digits. The three required fields fall back to an empty string, so that a server which deviates from the documented shape still decodes successfully.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var fields = [String: String]()

        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                fields[key.stringValue] = value
            } else if let value = try? container.decode(Int.self, forKey: key) {
                fields[key.stringValue] = String(value)
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                fields[key.stringValue] = String(value)
            } else if let value = try? container.decode(Double.self, forKey: key) {
                fields[key.stringValue] = String(value)
            }
        }

        type = fields.removeValue(forKey: "type") ?? ""
        id = fields.removeValue(forKey: "id") ?? ""
        name = fields.removeValue(forKey: "name") ?? ""
        path = fields.removeValue(forKey: "path")
        link = fields.removeValue(forKey: "link")
        other = fields
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a rich object.
    ///
    public var description: String {
        name
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a rich object.
    ///
    public var debugDescription: String {
        "\(type)#\(id): \(name)"
    }
}
