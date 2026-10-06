// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The rules by which the notes app turns a category into the folder below the notes folder that a note's file is placed in, for a client which wants to know the ``Note/category`` a note will have before or without asking the server.
///
/// The category of a note is the path of the folder its file is in, relative to the notes folder ``NotesSettings/notesPath`` names, so the notes app sanitizes every category it is given to ``Server/createNote(title:category:content:modification:isFavorite:)`` or ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``.
/// ``sanitize(_:)`` is pure, so it needs neither a ``Server`` nor a connection, and it can run on any thread, but a caller still adopts the ``Note/category`` the server returns, for the reasons ``NoteTitle`` lists.
///
public enum NoteCategory {
    ///
    /// Sanitize a category, such as one a user typed, as the notes app does before it creates the folders it names.
    ///
    /// The category is split into its components at every `/`, and each component is sanitized like a title in ``NoteTitle/sanitize(_:)``, except that it is neither cut to its first line nor cut off after a number of characters, and its white space is left as it is apart from trimming:
    ///
    /// - The characters `*`, `|`, `/`, `\`, `:`, `"`, `<`, `>` and `?` are removed, so a `\` does not separate components but disappears.
    /// - Dots and white space at the start of each line of a component are removed, so that the folder is not hidden, which also turns `..` into nothing and keeps a category from reaching outside the notes folder.
    /// - Spaces, tabs, line feeds and carriage returns are trimmed from both ends of a component.
    ///
    /// Components which end up empty are dropped, and the rest are joined with `/` again, so `/Work//Projects/` becomes `Work/Projects` and `Work/../Private` becomes `Work/Private`.
    ///
    /// - Parameter category: The category to sanitize, with `/` delimiting sub-categories.
    ///
    /// - Returns: The sanitized category, or an empty string when nothing remains of it, which files a note under no category at all.
    ///
    public static func sanitize(_ category: String) -> String {
        let components = category.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false)
        let sanitized = components.map { NoteNameSanitizer.sanitize(Array($0)) }

        return sanitized
            .filter { $0.isEmpty == false }
            .map { String(String.UnicodeScalarView($0)) }
            .joined(separator: "/")
    }
}
