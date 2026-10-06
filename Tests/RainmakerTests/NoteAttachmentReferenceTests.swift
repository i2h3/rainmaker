// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Rainmaker
import Testing

///
/// About referencing an attachment from a note's Markdown content through ``NoteAttachmentReference``, the way the Nextcloud Text app writes and reads such references.
///
/// These tests need neither a server nor response fixtures because all of its functions are pure.
/// The expected encodings equal what JavaScript's `encodeURIComponent` with `!`, `'`, `(`, `)` and `*` escaped in addition yields for each component, which is how Text encodes them.
///
@Suite("Note Attachment Reference") struct NoteAttachmentReferenceTests {
    @Test("Encodes each component of a path and decodes it again", arguments: [
        ("", ""),
        (".attachments.123/Photo (1).png", ".attachments.123/Photo%20%281%29.png"),
        ("a&b+c%d.png", "a%26b%2Bc%25d.png"),
        ("it's!*.png", "it%27s%21%2A.png"),
        ("a#b?c.png", "a%23b%3Fc.png"),
        ("[draft] scan.pdf", "%5Bdraft%5D%20scan.pdf"),
        ("~-_.", "~-_."),
        ("Café.png", "Caf%C3%A9.png"),
        ("Cafe\u{301}.png", "Cafe%CC%81.png"),
        ("😀.png", "%F0%9F%98%80.png"),
        ("../img/a b.png", "../img/a%20b.png"),
        ("a\\b.png", "a%5Cb.png"),
    ])
    func roundTrip(path: String, encoded: String) {
        #expect(NoteAttachmentReference.encode(path) == encoded)
        #expect(Array(NoteAttachmentReference.decode(encoded).unicodeScalars) == Array(path.unicodeScalars))
    }

    @Test("Decodes references which are not or not fully encoded", arguments: [
        ("Photo (1).png", "Photo (1).png"),
        ("a+b.png", "a+b.png"),
        ("100%.png", "100%.png"),
        ("50%2", "50%2"),
        ("%zz.png", "%zz.png"),
        ("%e2%82%ac.png", "€.png"),
        ("Photo%20(1).png", "Photo (1).png"),
        ("%FF.png", "%FF.png"),
        ("Café%20é.png", "Café é.png"),
    ])
    func decodeLegacy(reference: String, expected: String) {
        #expect(NoteAttachmentReference.decode(reference) == expected)
    }

    @Test("Builds the Markdown of a reference", arguments: [
        ("Photo (1).png", ".attachments.123/Photo (1).png", "![Photo (1).png](.attachments.123/Photo%20%281%29.png)"),
        ("[draft] scan", ".attachments.7/scan.pdf", "![draft scan](.attachments.7/scan.pdf)"),
        ("two\nlines", ".attachments.7/a.png", "![two lines](.attachments.7/a.png)"),
        ("", "a&b.png", "![](a%26b.png)"),
        ("evil\u{202E}gnp.exe", ".attachments.1/evil\u{202E}gnp.exe", "![evilgnp.exe](.attachments.1/evilgnp.exe)"),
        ("x", "\u{2066}dir\u{2069}/\u{200E}a.png", "![x](%E2%81%A6dir%E2%81%A9/a.png)"),
    ])
    func markdown(alt: String, path: String, expected: String) {
        #expect(NoteAttachmentReference.markdown(alt: alt, path: path) == expected)
    }

    @Test("Removes the characters controlling the direction of text from a file name")
    func sanitizeFileName() {
        let controls = "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"

        #expect(NoteAttachmentReference.sanitizeFileName("a" + controls + "b.png") == "ab.png")
        #expect(NoteAttachmentReference.sanitizeFileName("Café (1).png") == "Café (1).png")
    }
}
