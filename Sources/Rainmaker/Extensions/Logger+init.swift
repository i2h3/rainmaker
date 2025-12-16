// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import os

extension Logger {
    ///
    /// Convenience initializer for logger to automatically define the same subsystem string in a single place.
    ///
    init(category: String) {
        self.init(subsystem: "Rainmaker", category: category)
    }
}
