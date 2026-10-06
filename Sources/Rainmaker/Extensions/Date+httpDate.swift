// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension Date {
    ///
    /// Create a date from an HTTP date such as `"Sat, 01 Jan 2000 00:00:00 GMT"`, or fail when the string is not one.
    ///
    /// This is the format of the `Last-Modified` header the notes app sends with ``Server/notes(changedSince:)``, which becomes ``NoteChanges/lastModified``, and of the `getlastmodified` property WebDAV reports for every ``Item``, which is why the response parsing of both shares it.
    /// The formatter is pinned to the `en_US_POSIX` locale, so neither the language nor the calendar of the device can change how the English day and month names are read, and its zone pattern also accepts the literal `GMT` every such date ends with.
    ///
    /// A new formatter is built on every call rather than kept in a static property, because `DateFormatter` is not `Sendable` and the Foundation format style made for HTTP dates requires operating system releases newer than this package supports.
    ///
    /// - Parameters:
    ///     - string: The HTTP date to read.
    ///
    init?(httpDate string: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"

        guard let date = formatter.date(from: string) else {
            return nil
        }

        self = date
    }
}
