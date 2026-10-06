// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension NoteChanges: NoteChangeSet {
    ///
    /// Always `false`, because the notes ``NoteChanges/changed`` holds are decoded as ``Note``, which requires the content of each note, so the listings returning these changes never ask the server to leave it out.
    ///
    static let excludesContent = false
}
