// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The removal of the Markdown syntax the notes app removes from a note's content before it takes a title from it, which is what ``NoteTitle/derive(fromContent:)`` builds on.
///
/// It runs four passes over the whole content, one after the other, each of which scans the content once from its start and continues behind whatever it removed:
///
/// 1. A list marker, which is `*`, `+` or `-` followed by white space at the start of a line, is removed along with the white space around it.
/// 2. A heading, which is a line starting with one or more `#` followed by white space, is reduced to its text without the trailing white space and `#`.
/// 3. A line which consists of nothing but `=` or nothing but `-`, which underlines a heading in the other Markdown syntax for headings, is emptied.
/// 4. Emphasis, which is text between two equal runs of `*` or `_` on one line, is reduced to the text between them.
///
/// Every pass but the one removing emphasis takes time proportional to the length of the content, and that one does as well for realistic content, while its worst case, a line of runs of delimiters which get shorter one after the other, grows with the length of the line times its square root, so that even content made to be pathological, such as a heading followed by a long run of spaces, cannot stall a caller.
/// Like ``NoteNameSanitizer``, it works on Unicode scalars, considers white space what ``NoteNameSanitizer/isWhitespace(_:)`` does, which includes line feeds, and starts a new line only after a line feed, so that a carriage return of a Windows line ending is part of the line it ends.
///
enum NoteMarkdownStripper {
    ///
    /// The content with the four passes described above applied.
    ///
    static func strip(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let withoutListMarkers = removingListMarkers(scalars)
        let withoutHeadingMarkers = removingHeadingMarkers(withoutListMarkers)
        let withoutUnderlines = removingUnderlines(withoutHeadingMarkers)

        return removingEmphasis(withoutUnderlines)
    }

    ///
    /// Whether a line starts at the index, which is the case at the very start and right behind every line feed.
    ///
    private static func startsLine(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        index == 0 || scalars[index - 1] == "\n"
    }

    ///
    /// The index of the first scalar at or after `index` which is not white space, or the end of the scalars.
    ///
    private static func endOfWhitespace(_ scalars: [Unicode.Scalar], from index: Int) -> Int {
        var end = index

        while end < scalars.count, NoteNameSanitizer.isWhitespace(scalars[end]) {
            end += 1
        }

        return end
    }

    ///
    /// The index of the first scalar at or after `index` which differs from `scalar`, or the end of the scalars.
    ///
    private static func endOfRun(of scalar: Unicode.Scalar, in scalars: [Unicode.Scalar], from index: Int) -> Int {
        var end = index

        while end < scalars.count, scalars[end] == scalar {
            end += 1
        }

        return end
    }

    ///
    /// Whether a line ends at the index, which is the case at the very end and right before every line feed.
    ///
    private static func endsLine(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        index == scalars.count || scalars[index] == "\n"
    }

    ///
    /// The first pass of ``strip(_:)``, which removes list markers along with the white space before and after them.
    ///
    /// The white space before a marker may span blank lines, and the white space after it may span line breaks, so a marker alone on its line takes the line break and the indentation of the next line with it.
    ///
    private static func removingListMarkers(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)
        var index = 0

        while index < scalars.count {
            if startsLine(scalars, at: index) {
                let marker = endOfWhitespace(scalars, from: index)

                if marker + 1 < scalars.count, ["*", "+", "-"].contains(scalars[marker]), NoteNameSanitizer.isWhitespace(scalars[marker + 1]) {
                    index = endOfWhitespace(scalars, from: marker + 1)
                    continue
                }

                // Every line starting within the white space ends it at the same place and fails alike, so it is kept as a whole.
                if marker > index {
                    result.append(contentsOf: scalars[index ..< marker])
                    index = marker
                    continue
                }
            }

            result.append(scalars[index])
            index += 1
        }

        return result
    }

    ///
    /// The second pass of ``strip(_:)``, which reduces headings to their text.
    ///
    /// The text of a heading is the shortest one after which nothing but white space and `#` remain up to the end of a line, and whatever follows it up to there is removed as well.
    /// The white space which separates the `#` from the text may span line breaks, so a `#` alone on its line turns the next line into the heading.
    ///
    private static func removingHeadingMarkers(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)
        var index = 0

        while index < scalars.count {
            if startsLine(scalars, at: index), scalars[index] == "#" {
                let separator = endOfRun(of: "#", in: scalars, from: index)

                if separator < scalars.count, NoteNameSanitizer.isWhitespace(scalars[separator]) {
                    let textStart = endOfWhitespace(scalars, from: separator)
                    var textEnd = textStart

                    while true {
                        if let end = endOfHeadingClosing(scalars, from: textEnd) {
                            result.append(contentsOf: scalars[textStart ..< textEnd])
                            index = end
                            break
                        }

                        // A closing starting anywhere within the same white space and `#` fails alike, so the text grows past them at once, and as the closing always matches at the end of a line, the text never grows past it.
                        textEnd = max(textEnd + 1, endOfRun(of: "#", in: scalars, from: endOfWhitespace(scalars, from: textEnd)))
                    }

                    continue
                }
            }

            result.append(scalars[index])
            index += 1
        }

        return result
    }

    ///
    /// The end of what closes a heading whose text ends at `index`, which is white space followed by `#` followed by the end of a line, preferring as much white space and then as many `#` as possible, or `nil` when nothing closes it there.
    ///
    /// Taking less white space than there is only helps when the white space includes a line feed, at which a line ends, so the last line feed within it closes the heading when the `#` after all of it do not.
    ///
    private static func endOfHeadingClosing(_ scalars: [Unicode.Scalar], from index: Int) -> Int? {
        let hashes = endOfWhitespace(scalars, from: index)
        let end = endOfRun(of: "#", in: scalars, from: hashes)

        if endsLine(scalars, at: end) {
            return end
        }

        return scalars[index ..< hashes].lastIndex(of: "\n")
    }

    ///
    /// The third pass of ``strip(_:)``, which empties lines consisting of nothing but `=` or nothing but `-` while keeping their line breaks.
    ///
    private static func removingUnderlines(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)
        var index = 0

        while index < scalars.count {
            if startsLine(scalars, at: index), scalars[index] == "=" || scalars[index] == "-" {
                let end = endOfRun(of: scalars[index], in: scalars, from: index)

                if endsLine(scalars, at: end) {
                    index = end
                    continue
                }
            }

            result.append(scalars[index])
            index += 1
        }

        return result
    }

    ///
    /// The fourth pass of ``strip(_:)``, which reduces emphasized text to the text between its delimiters.
    ///
    /// A run of `*` or `_` opens emphasis wherever it is, even within a word, and the same run closes it at the nearest place on the same line, so `snake_case_name` loses its underscores.
    /// When no run of the full length closes it, shorter runs are tried, so `***a**` keeps one `*` and yields `*a`, and the opening run may close itself, so `****` yields nothing.
    ///
    private static func removingEmphasis(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)
        var index = 0

        while index < scalars.count {
            let delimiter = scalars[index]

            if delimiter == "*" || delimiter == "_", let emphasis = emphasis(of: delimiter, in: scalars, at: index) {
                result.append(contentsOf: scalars[index + emphasis.length ..< emphasis.closing])
                index = emphasis.closing + emphasis.length
                continue
            }

            result.append(delimiter)
            index += 1
        }

        return result
    }

    ///
    /// The length of the delimiters and the index of the closing delimiter of the emphasis the run of `delimiter` at `index` opens, or `nil` when it opens none.
    ///
    /// The longest delimiter which is closed anywhere on the line wins, and of the places closing it the nearest one.
    /// The rest of the opening run closes a delimiter of up to half its length right behind it, and any later run on the same line closes a delimiter of up to its own length at its start.
    /// The line is only scanned as far as a later run as long as the opening one, which closes all of it.
    ///
    private static func emphasis(of delimiter: Unicode.Scalar, in scalars: [Unicode.Scalar], at index: Int) -> (length: Int, closing: Int)? {
        let opening = endOfRun(of: delimiter, in: scalars, from: index) - index
        var laterRuns: [(start: Int, length: Int)] = []
        var position = index + opening

        while position < scalars.count, scalars[position] != "\n" {
            guard scalars[position] == delimiter else {
                position += 1
                continue
            }

            let length = endOfRun(of: delimiter, in: scalars, from: position) - position
            laterRuns.append((start: position, length: length))

            if length >= opening {
                break
            }

            position += length
        }

        let longestLater = min(laterRuns.map(\.length).max() ?? 0, opening)
        let length = max(longestLater, opening / 2)

        guard length > 0 else {
            return nil
        }

        if 2 * length <= opening {
            return (length: length, closing: index + length)
        }

        guard let closing = laterRuns.first(where: { $0.length >= length }) else {
            return nil
        }

        return (length: length, closing: closing.start)
    }
}
