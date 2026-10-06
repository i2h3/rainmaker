// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The way a note's Markdown content references an attachment, as the Nextcloud Text app, which is the notes app's rich editor, writes and reads such references.
///
/// Adding an attachment through ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` does not change the note, it only stores the file and returns its path relative to the folder of the note's category, which releases of the notes app keeping attachments per note, see ``Notes/storesAttachmentsPerNote``, shape like `.attachments.<id>/<name>`.
/// To embed the file, a caller inserts a reference such as the one ``markdown(alt:path:)`` builds into the note's content and changes the note through ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``.
/// Inserting it matters beyond showing the file: once a Markdown note has been opened in Text, a background job of Text deletes, whenever nobody is editing the note, every file in the note's `.attachments.<id>` folder which the content does not reference as `![…](.attachments.<id>/<encoded name>)`, comparing the name it decodes from the reference with the file name, so an attachment which is not referenced, or referenced with another encoding, is lost.
/// In the other direction, ``decode(_:)`` turns the target of a reference back into the path ``Server/attachment(at:ofNote:)`` takes, and ``NoteAttachmentPath/resolve(_:relativeTo:)`` says which file in the notes folder it names.
///
/// All of these are pure, so they need neither a ``Server`` nor a connection, and they can run on any thread.
///
public enum NoteAttachmentReference {
    ///
    /// The invisible characters which control the direction of text and which Text removes from a file name before it references the file, so that a name cannot pretend to have another extension than it has, which are U+200E, U+200F, U+202A to U+202E and U+2066 to U+2069.
    ///
    static let bidirectionalControls: Set<Unicode.Scalar> = [
        "\u{200E}", "\u{200F}",
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ]

    ///
    /// The digits of a hexadecimal number in upper case, as ``encode(_:)`` writes an escaped byte.
    ///
    static let hexadecimalDigits: [Unicode.Scalar] = Array("0123456789ABCDEF".unicodeScalars)

    ///
    /// Whether ``encode(_:)`` writes the byte as it is, which only the ASCII letters and digits and `-`, `_`, `.` and `~` are.
    ///
    static func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
            case UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
                true
            default:
                false
        }
    }

    ///
    /// The value of a hexadecimal digit in either case, or `nil` when the scalar is no such digit, which is how ``decode(_:)`` tells an escaped byte from a `%` which is meant literally.
    ///
    static func hexadecimalValue(of scalar: Unicode.Scalar) -> UInt8? {
        switch scalar {
            case "0" ... "9":
                UInt8(scalar.value - Unicode.Scalar("0").value)
            case "A" ... "F":
                UInt8(scalar.value - Unicode.Scalar("A").value + 10)
            case "a" ... "f":
                UInt8(scalar.value - Unicode.Scalar("a").value + 10)
            default:
                nil
        }
    }

    ///
    /// Percent-encode a path relative to the folder of a note's category for use as the target of a Markdown reference in the note's content.
    ///
    /// Each component the path's `/` delimit is encoded on its own, keeping the `/` between them, so `.attachments.123/Photo (1).png` becomes `.attachments.123/Photo%20%281%29.png`.
    /// Every byte of a component's UTF-8 representation except the ASCII letters and digits and `-`, `_`, `.` and `~` is written as `%` followed by two upper case hexadecimal digits.
    /// That is what JavaScript's `encodeURIComponent` does plus escaping `!`, `'`, `(`, `)` and `*`, which is how Text writes references and what it expects when it looks for them: a `)` would end the Markdown link early, an `&` ends the name Text reads, and a `+` would be read back as a space.
    ///
    /// - Parameter relativePath: The path as ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` returned it.
    ///
    /// - Returns: The percent-encoded path.
    ///
    public static func encode(_ relativePath: String) -> String {
        var encoded = String.UnicodeScalarView()

        for byte in relativePath.utf8 {
            if byte == UInt8(ascii: "/") || isUnreserved(byte) {
                encoded.append(Unicode.Scalar(byte))
            } else {
                encoded.append("%")
                encoded.append(hexadecimalDigits[Int(byte >> 4)])
                encoded.append(hexadecimalDigits[Int(byte & 0x0F)])
            }
        }

        return String(encoded)
    }

    ///
    /// Decode the target of a Markdown reference in a note's content into the path ``Server/attachment(at:ofNote:)`` and ``NoteAttachmentPath/resolve(_:relativeTo:)`` take.
    ///
    /// Every `%` followed by two hexadecimal digits in either case stands for the byte they spell, and the bytes are read as UTF-8.
    /// A `+` stays a `+`, as it does for the notes app's own Markdown preview, which reads references with JavaScript's `decodeURIComponent`.
    /// References written by hand or by older editors are often not encoded at all, so a `%` which is not followed by two hexadecimal digits is kept as it is, and a reference whose decoded bytes are not valid UTF-8 is returned unchanged rather than failing.
    ///
    /// - Parameter reference: The target of the reference, which is what stands between the parentheses of `![…](…)`.
    ///
    /// - Returns: The decoded path, relative to the folder of the note's category.
    ///
    public static func decode(_ reference: String) -> String {
        let scalars = Array(reference.unicodeScalars)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(scalars.count)
        var index = 0

        while index < scalars.count {
            if scalars[index] == "%", index + 2 < scalars.count, let high = hexadecimalValue(of: scalars[index + 1]), let low = hexadecimalValue(of: scalars[index + 2]) {
                bytes.append(high << 4 | low)
                index += 3
                continue
            }

            bytes.append(contentsOf: String(scalars[index]).utf8)
            index += 1
        }

        return String(bytes: bytes, encoding: .utf8) ?? reference
    }

    ///
    /// Build the Markdown which embeds an attachment into a note's content the way Text does, such as `![Photo (1).png](.attachments.123/Photo%20%281%29.png)`.
    ///
    /// The invisible characters which control the direction of text, see ``sanitizeFileName(_:)``, are removed from the file name, which is the last component of the path, before it is encoded through ``encode(_:)``, as Text does.
    /// Text compares the name it decodes from a reference with the name of the file, so a file whose stored name contains such characters is not recognized by the reference built here and would be deleted by Text's background job, which is why a file name is best passed through ``sanitizeFileName(_:)`` before it is uploaded.
    /// The alternative text loses `[` and `]`, which would end it early, as well as those invisible characters, and line breaks in it become spaces, so that it cannot split the reference.
    ///
    /// - Parameters:
    ///     - alt: The alternative text which describes the attachment, for which Text uses the file name.
    ///     - path: The path of the attachment relative to the folder of the note's category, as ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` returned it.
    ///
    /// - Returns: The Markdown of the reference, without a line break before or after it.
    ///
    public static func markdown(alt: String, path: String) -> String {
        var components = path.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }

        if let last = components.indices.last {
            components[last] = sanitizeFileName(components[last])
        }

        var text = String.UnicodeScalarView()

        for scalar in alt.unicodeScalars where scalar != "[" && scalar != "]" && bidirectionalControls.contains(scalar) == false {
            text.append(NoteNameSanitizer.isLineBreak(scalar) ? " " : scalar)
        }

        return "![\(String(text))](\(encode(components.joined(separator: "/"))))"
    }

    ///
    /// Remove the invisible characters which control the direction of text from a file name, as Text does before it references a file.
    ///
    /// Such characters can make a name appear to have another extension than it has, which is why Text leaves them out of references, see ``markdown(alt:path:)``.
    /// Passing a file name through this before handing it to ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` makes the name the server stores the file under match the name a reference to it decodes to.
    ///
    /// - Parameter fileName: The file name to sanitize.
    ///
    /// - Returns: The file name without the characters U+200E, U+200F, U+202A to U+202E and U+2066 to U+2069.
    ///
    public static func sanitizeFileName(_ fileName: String) -> String {
        String(String.UnicodeScalarView(fileName.unicodeScalars.filter { bidirectionalControls.contains($0) == false }))
    }
}
