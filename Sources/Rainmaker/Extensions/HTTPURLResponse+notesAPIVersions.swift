// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension HTTPURLResponse {
    ///
    /// The versions of the notes API the responding notes app advertises in its `X-Notes-API-Versions` header, e.g. `["0.2", "1.3", "1.4"]`.
    ///
    /// The header value is split at its commas and every entry is trimmed, while empty entries are dropped.
    /// The result is empty when the header is absent, which is also what tells a response the notes app produced apart from one the server or a proxy produced on its own behalf, because the app adds the header to every response it sends itself.
    /// The notes features of ``Server`` use this both to enforce ``Notes/minimumAPIVersion`` through ``Notes/supports(apiVersions:)`` and as the gate deciding whether a status carries the notes app's meaning when mapping it onto a ``RainmakerError``.
    ///
    var notesAPIVersions: [String] {
        (value(forHTTPHeaderField: "X-Notes-API-Versions") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
    }
}
