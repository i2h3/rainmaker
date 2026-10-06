// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Rainmaker
import Testing

///
/// About predicting the ``Note/category`` the notes app files a note under through ``NoteCategory/sanitize(_:)``.
///
/// These tests need neither a server nor response fixtures because the function is pure.
/// The expected categories were checked against the behaviour of the notes app's own category handling, and they are compared scalar by scalar, so that a decomposed letter does not pass for its composed form.
///
@Suite("Note Category") struct NoteCategoryTests {
    @Test("Sanitizes a category component by component", arguments: [
        ("", ""),
        ("Work", "Work"),
        ("Work/Projects", "Work/Projects"),
        ("/Work//Projects/", "Work/Projects"),
        (" Work / Projects ", "Work/Projects"),
        ("Work/../Private", "Work/Private"),
        ("..", ""),
        ("../..", ""),
        ("../etc/passwd", "etc/passwd"),
        (".hidden/x", "hidden/x"),
        ("\u{A0}Work", "Work"),
        ("Work\u{A0}/x", "Work\u{A0}/x"),
        ("a\\b", "ab"),
        ("C:/x", "C/x"),
        ("What?/Why*", "What/Why"),
        ("Fish & Chips/1+1/100%", "Fish & Chips/1+1/100%"),
        ("Reports (1)", "Reports (1)"),
        ("Café/e\u{301}", "Café/e\u{301}"),
        ("😀/x", "😀/x"),
        ("# Heading/_em_", "# Heading/_em_"),
        ("0", "0"),
        ("Line one\nLine two", "Line one\nLine two"),
    ])
    func sanitize(category: String, expected: String) {
        #expect(Array(NoteCategory.sanitize(category).unicodeScalars) == Array(expected.unicodeScalars))
    }

    @Test("Does not cut a component off")
    func noCutOff() {
        // Unlike a title, a category component is neither cut to its first line nor to a number of characters.
        let component = String(repeating: "a", count: 150)

        #expect(NoteCategory.sanitize(component + "/" + component) == component + "/" + component)
    }
}
