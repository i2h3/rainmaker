// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Rainmaker
import Testing

///
/// About predicting the ``Note/title`` the notes app gives a note through ``NoteTitle/derive(fromContent:)`` and ``NoteTitle/sanitize(_:)``.
///
/// These tests need neither a server nor response fixtures because both functions are pure.
/// The expected titles were checked against the behaviour of the notes app's own title handling, and they are compared scalar by scalar, so that a decomposed letter does not pass for its composed form.
///
@Suite("Note Title") struct NoteTitleTests {
    @Test("Derives the title from content", arguments: [
        ("", ""),
        ("   \n\n  ", ""),
        ("Hello World", "Hello World"),
        ("# Heading", "Heading"),
        ("## Heading ##", "Heading"),
        ("# C#", "C"),
        ("#hashtag", "#hashtag"),
        ("C# basics", "C# basics"),
        ("\n\n# Shopping list\n- Milk", "Shopping list"),
        ("Title\n=====\nBody", "Title"),
        ("===\nBody", "Body"),
        ("Title\r\n-----", "Title"),
        ("- item", "item"),
        ("* item\n* second", "item"),
        ("+ item", "item"),
        ("  - indented item", "indented item"),
        ("**bold** text", "bold text"),
        ("_em_ and __strong__", "em and strong"),
        ("snake_case_name", "snakecasename"),
        ("***a**", "a"),
        ("****", ""),
        ("Café", "Café"),
        ("Cafe\u{301}", "Cafe\u{301}"),
        ("Notes 😀", "Notes 😀"),
        ("Report (1)", "Report (1)"),
        ("Fish & Chips", "Fish & Chips"),
        ("1 + 1 = 2", "1 + 1 = 2"),
        ("100% done", "100% done"),
        ("a/b\\c:d*e|f\"g<h>i?", "abcdefghi"),
        ("../etc/passwd", "etcpasswd"),
        ("...hidden", "hidden"),
        ("  \t leading", "leading"),
        ("\u{A0}Work", "Work"),
        ("Work\u{A0}", "Work"),
        ("tab\there", "tab here"),
        ("double  space", "double  space"),
        ("no-break\u{A0}space", "no-break space"),
        ("first\r\nsecond", "first"),
        ("first\u{2028}second", "first"),
        ("0", ""),
        ("# 0", ""),
    ])
    func derive(content: String, expected: String) {
        #expect(Array(NoteTitle.derive(fromContent: content).unicodeScalars) == Array(expected.unicodeScalars))
    }

    @Test("Sanitizes a typed title", arguments: [
        ("", ""),
        ("Hello World", "Hello World"),
        ("# Shopping list", "# Shopping list"),
        ("- item", "- item"),
        ("_em_ and __strong__", "_em_ and __strong__"),
        ("**bold** text", "bold text"),
        ("===\nBody", "==="),
        ("Line one\nLine two", "Line one"),
        ("first\u{2028}second", "first"),
        ("Café", "Café"),
        ("Cafe\u{301}", "Cafe\u{301}"),
        ("Notes 😀", "Notes 😀"),
        ("Report (1)", "Report (1)"),
        ("Fish & Chips", "Fish & Chips"),
        ("1+1", "1+1"),
        ("100%", "100%"),
        ("a/b\\c:d*e|f\"g<h>i?", "abcdefghi"),
        ("..", ""),
        ("../etc/passwd", "etcpasswd"),
        ("...hidden", "hidden"),
        ("Work\u{A0}", "Work "),
        ("tab\there", "tab here"),
        ("0", ""),
        ("00", "00"),
    ])
    func sanitize(title: String, expected: String) {
        #expect(Array(NoteTitle.sanitize(title).unicodeScalars) == Array(expected.unicodeScalars))
    }

    @Test("Cuts the title off after 100 Unicode scalars", arguments: [
        (String(repeating: "a", count: 150), String(repeating: "a", count: 100)),
        (String(repeating: "e\u{301}", count: 60), String(repeating: "e\u{301}", count: 50)),
        (String(repeating: "😀", count: 101), String(repeating: "😀", count: 100)),
        (String(repeating: "👨‍👩‍👧", count: 21), String(repeating: "👨‍👩‍👧", count: 20)),
    ])
    func cutOff(text: String, expected: String) {
        #expect(Array(NoteTitle.sanitize(text).unicodeScalars) == Array(expected.unicodeScalars))
        #expect(Array(NoteTitle.derive(fromContent: text).unicodeScalars) == Array(expected.unicodeScalars))
    }

    @Test("Removes the space a cut leaves at the end only when deriving")
    func cutOffAtSpace() {
        // The server sanitizes a derived title a second time when it names the file, which trims the space, while a typed title is sanitized once.
        let text = String(repeating: "a", count: 99) + " b"

        #expect(NoteTitle.derive(fromContent: text) == String(repeating: "a", count: 99))
        #expect(NoteTitle.sanitize(text) == String(repeating: "a", count: 99) + " ")
    }

    @Test("Takes no time to speak of for content made to be pathological")
    func pathologicalContent() {
        // Each of these makes a naive backtracking matcher take quadratic time or worse, which is why the notes app's own matcher gives up on the first one, while smaller variants of them yield what the notes app derives.
        #expect(NoteTitle.derive(fromContent: "# a" + String(repeating: " ", count: 100_000) + "b") == "a")
        #expect(NoteTitle.derive(fromContent: String(repeating: "*", count: 100_000)) == "")
        #expect(NoteTitle.derive(fromContent: String(repeating: "\n", count: 100_000) + "- x") == "x")
        #expect(NoteTitle.derive(fromContent: (1 ... 400).reversed().map { String(repeating: "*", count: $0) + "a" }.joined()) == String(repeating: "a", count: 100))
    }
}
