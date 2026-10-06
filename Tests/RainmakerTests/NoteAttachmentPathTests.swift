// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Rainmaker
import Testing

///
/// About resolving the path of an attachment relative to the folder of a note's category through ``NoteAttachmentPath/resolve(_:relativeTo:)``, as the notes app does when it serves ``Server/attachment(at:ofNote:)``.
///
/// These tests need neither a server nor response fixtures because the function is pure.
///
@Suite("Note Attachment Path") struct NoteAttachmentPathTests {
    @Test("Resolves a path relative to the folder of a category", arguments: [
        (".attachments.12/a.png", "", ".attachments.12/a.png"),
        (".attachments.12/a.png", "Work", "Work/.attachments.12/a.png"),
        (".attachments.12/a.png", "Work/Projects", "Work/Projects/.attachments.12/a.png"),
        ("../img/a.png", "Work/Projects", "Work/img/a.png"),
        ("../../../../x.png", "Work", "x.png"),
        ("../x.png", "", "x.png"),
        ("..\\x.png", "Work", "x.png"),
        ("img\\a.png", "Work", "Work/img/a.png"),
        ("//a///b.png/", "Work", "Work/a/b.png"),
        ("./a.png", "Work", "Work/a.png"),
        ("a/./../b.png", "Work", "Work/a/b.png"),
        ("a/b/../../c.png", "Work", "Work/c.png"),
        ("...png", "Work", "Work/...png"),
        ("Café é (1).png", "Reisen", "Reisen/Café é (1).png"),
        ("Cafe\u{301}.png", "", "Cafe\u{301}.png"),
        ("😀 & + %.png", "", "😀 & + %.png"),
        ("a%20b.png", "", "a%20b.png"),
    ])
    func resolve(path: String, category: String, expected: String) {
        let resolved = NoteAttachmentPath.resolve(path, relativeTo: category)

        #expect(resolved.map { Array($0.unicodeScalars) } == Array(expected.unicodeScalars))
    }

    @Test("Resolves nothing for the notes folder itself", arguments: [
        ("", ""),
        ("/", ""),
        ("..", "Work"),
        ("../..", "Work/Projects"),
        (".", ""),
        ("a/..", ""),
    ])
    func notesFolder(path: String, category: String) {
        #expect(NoteAttachmentPath.resolve(path, relativeTo: category) == nil)
    }
}
