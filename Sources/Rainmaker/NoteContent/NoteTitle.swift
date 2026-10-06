// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The rules by which the notes app turns a note's content or a typed title into the ``Note/title`` it gives the note, for a client which wants to know that title before or without asking the server.
///
/// The title of a note is the name of its file without the extension, so the notes app sanitizes every title it is given, and the notes API of version 1 never derives one from the content: a client which wants the title the web interface would show for some text, for example a Shortcuts action creating a note from text, derives it through ``derive(fromContent:)`` and passes it to ``Server/createNote(title:category:content:modification:isFavorite:)`` or ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``.
/// Both functions are pure, so they need neither a ``Server`` nor a connection, and they can run on any thread.
///
/// They predict the server's result, but they do not replace it, and a caller still adopts the ``Note/title`` the server returns:
///
/// - The server sanitizes the title it is given once more and returns its localized default title, such as "New note", where these return an empty string.
/// - When the category already holds a note of the title, the server appends a number such as `" (2)"`, shortening the title to keep it within 100 characters.
/// - A server whose database cannot store characters outside the Basic Multilingual Plane, such as most emoji, removes those as well, which these do not, because whether it does is not visible to a client.
/// - The server may store the name in another Unicode normalization form, which `String` comparison treats as equal anyway.
///
public enum NoteTitle {
    ///
    /// The number of Unicode scalars the notes app keeps of a title, which counts a decomposed letter and its combining mark as two.
    ///
    static let maximumLength = 100

    ///
    /// Derive the title the notes app's web interface gives a note from the note's content.
    ///
    /// The Markdown syntax of the content is stripped first: list markers, the `#` of headings, lines underlining a heading with `=` or `-`, and the `*` and `_` delimiting emphasis, even within words.
    /// The result is then sanitized as ``sanitize(_:)`` describes, which keeps the first line which is not blank, and sanitized once more, as the server does when it uses the title, which removes white space left at the end by cutting the title off.
    ///
    /// - Parameter content: The text of the note, as ``Note/content`` holds it.
    ///
    /// - Returns: The title, or an empty string when nothing remains of the content, in which case the server uses its localized default title such as "New note" instead.
    ///
    public static func derive(fromContent content: String) -> String {
        let stripped = NoteMarkdownStripper.strip(Array(content.unicodeScalars))
        let firstPass = sanitize(String(String.UnicodeScalarView(stripped)))

        guard firstPass.isEmpty == false else {
            return ""
        }

        return sanitize(firstPass)
    }

    ///
    /// Sanitize a title, such as one a user typed, as the notes app does before it names a note's file after it.
    ///
    /// - The characters `*`, `|`, `/`, `\`, `:`, `"`, `<`, `>` and `?` are removed, because some operating systems do not allow them in file names.
    /// - Dots and white space at the start are removed, so that the file is not hidden, and blank lines at the start disappear along with them.
    /// - Only the first line is kept, where a line feed, a carriage return, a vertical tab, a form feed, the next line control and the Unicode line and paragraph separators all end a line.
    /// - Every remaining white space character, such as a tab or a no-break space, becomes a plain space, while consecutive spaces are kept as they are.
    /// - The title is cut off after 100 Unicode scalars, which counts a decomposed letter and its combining mark as two and an emoji made of several scalars as several.
    ///
    /// Markdown syntax is kept, so that a title such as `# Shopping list` stays as it is, while ``derive(fromContent:)`` would turn the same text into `Shopping list`.
    ///
    /// - Parameter title: The title to sanitize.
    ///
    /// - Returns: The sanitized title, or an empty string when nothing remains of it or it is `"0"`, which the notes app treats as empty, in both of which cases the server uses its localized default title such as "New note" instead.
    ///
    public static func sanitize(_ title: String) -> String {
        let sanitized = NoteNameSanitizer.sanitize(Array(title.unicodeScalars))
        let firstLine = sanitized.prefix { NoteNameSanitizer.isLineBreak($0) == false }
        let trimmed = NoteNameSanitizer.trimmed(Array(firstLine))
        let spaced = trimmed.map { NoteNameSanitizer.isWhitespace($0) ? " " : $0 }
        let result = String(String.UnicodeScalarView(spaced.prefix(maximumLength)))

        guard result != "0" else {
            return ""
        }

        return result
    }
}
