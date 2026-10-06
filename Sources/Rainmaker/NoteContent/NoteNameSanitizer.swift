// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The rules by which the notes app turns a title or a component of a category into a name it can give a file or a folder.
///
/// ``NoteTitle`` and ``NoteCategory`` are built on it, which is why it works on Unicode scalars rather than on characters: the notes app counts and matches code points, so a decomposed letter followed by its combining mark counts as two of them, as it does here.
/// The character classes below are those the notes app's pattern matching uses, which are not the ones of Foundation's character sets.
///
enum NoteNameSanitizer {
    ///
    /// The characters the notes app removes from every title and from every component of a category, because some operating systems do not allow them in file names, and because `/` and `\` would otherwise place a file elsewhere.
    ///
    static let removedCharacters: Set<Unicode.Scalar> = ["*", "|", "/", "\\", ":", "\"", "<", ">", "?"]

    ///
    /// The characters the notes app trims from both ends of a name, which are only these few ASCII characters and not every kind of white space ``isWhitespace(_:)`` recognizes.
    ///
    static let trimmedCharacters: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\0", "\u{0B}"]

    ///
    /// Whether the notes app's pattern matching considers the scalar white space, which are the ASCII tab, line feed, vertical tab, form feed, carriage return and space, the next line control, the Unicode line and paragraph separators and the horizontal spaces of Unicode such as the no-break space, the ideographic space and the Mongolian vowel separator.
    ///
    /// This is a fixed list rather than a Unicode property, because the list the notes app's pattern matching uses differs from every property: it includes the next line control, which Unicode classifies as a control character rather than a separator, and the Mongolian vowel separator, which Unicode no longer considers a space, but not the zero width space.
    ///
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
            case 0x09 ... 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x180E, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
                true
            default:
                false
        }
    }

    ///
    /// Whether the scalar ends a line where the notes app takes the first line of a title, which besides line feed and carriage return are the vertical tab, the form feed, the next line control and the Unicode line and paragraph separators.
    ///
    static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
            case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029:
                true
            default:
                false
        }
    }

    ///
    /// The name with ``removedCharacters`` removed, with any dots and white space at the start of each of its lines removed so that the file is not hidden, and with ``trimmedCharacters`` trimmed from both ends.
    ///
    /// Only a line feed starts a new line here, and the white space removed at the start of a line includes line feeds, so blank lines at the start of the name disappear along with the indentation of the first line which is not blank.
    ///
    static func sanitize(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let kept = scalars.filter { removedCharacters.contains($0) == false }
        var visible: [Unicode.Scalar] = []
        visible.reserveCapacity(kept.count)
        var index = 0

        while index < kept.count {
            if index == 0 || kept[index - 1] == "\n" {
                var end = index

                while end < kept.count, kept[end] == "." || isWhitespace(kept[end]) {
                    end += 1
                }

                if end > index {
                    index = end
                    continue
                }
            }

            visible.append(kept[index])
            index += 1
        }

        return trimmed(visible)
    }

    ///
    /// The scalars with ``trimmedCharacters`` removed from both ends.
    ///
    static func trimmed(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        guard let first = scalars.firstIndex(where: { trimmedCharacters.contains($0) == false }) else {
            return []
        }

        guard let last = scalars.lastIndex(where: { trimmedCharacters.contains($0) == false }) else {
            return []
        }

        return Array(scalars[first ... last])
    }
}
