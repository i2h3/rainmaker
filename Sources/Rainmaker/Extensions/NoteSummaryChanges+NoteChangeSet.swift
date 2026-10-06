// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension NoteSummaryChanges: NoteChangeSet {
    ///
    /// Always `true`, because leaving out the content of every note is what the listings returning these changes, such as ``Server/noteSummaries(changedSince:)``, exist for, and ``NoteSummary`` has no property to hold it.
    ///
    static let excludesContent = true
}
