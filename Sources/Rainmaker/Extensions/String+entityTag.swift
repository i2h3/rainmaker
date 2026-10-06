// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension String {
    ///
    /// This entity tag wrapped in double quotes, as the `If-None-Match` and `If-Match` headers require it, unless it is quoted already.
    ///
    /// The notes features of ``Server`` hand out entity tags without quotes, for example as ``NoteChanges/entityTag``, while the server only answers a conditional request with `304 Not Modified` when the header repeats the quoted tag exactly.
    /// Apply it to ``unquotedEntityTag`` rather than to a tag of unknown shape, so that a weak tag does not end up quoted around its `W/` prefix.
    ///
    var quotedEntityTag: String {
        guard count >= 2, hasPrefix("\""), hasSuffix("\"") else {
            return "\"\(self)\""
        }

        return self
    }

    ///
    /// This entity tag without a leading `W/` and without the double quotes around it, e.g. `"abc"` for `W/"abc"`.
    ///
    /// This is the form in which the notes features of ``Server`` hand out the `ETag` header of a response, for example as ``NoteChanges/entityTag``.
    /// The weakness marker is dropped on purpose: a proxy compressing a response may weaken its tag, while the server compares a conditional request against the strong tag it computed, so only the bare value turned back into a header by ``quotedEntityTag`` can still be answered with `304 Not Modified`.
    ///
    var unquotedEntityTag: String {
        var tag = trimmingCharacters(in: .whitespaces)

        if tag.hasPrefix("W/") {
            tag.removeFirst(2)
        }

        if tag.count >= 2, tag.hasPrefix("\""), tag.hasSuffix("\"") {
            tag.removeFirst()
            tag.removeLast()
        }

        return tag
    }
}
