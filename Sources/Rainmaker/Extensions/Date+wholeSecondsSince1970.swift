// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension Date {
    ///
    /// This date as a whole number of seconds since the Unix epoch, or `nil` when it cannot be expressed that way.
    ///
    /// This is what ``Server`` sends in the `X-OC-Mtime` header to preserve the modification date of an uploaded file, which is why the result is deliberately narrow.
    /// It is `nil` for a date at or before the Unix epoch, because the server cannot store such a modification date and records the upload time instead, and for a date whose interval is not a finite number.
    ///
    /// The conversion explicitly targets `Int64` and is checked rather than truncating.
    /// `Int` is only 32 bits wide on some of the platforms this package supports, where converting an out of range interval such as that of `Date.distantFuture` traps and terminates the process.
    ///
    var wholeSecondsSince1970: Int64? {
        guard let seconds = Int64(exactly: timeIntervalSince1970.rounded(.down)), seconds > 0 else {
            return nil
        }

        return seconds
    }
}
