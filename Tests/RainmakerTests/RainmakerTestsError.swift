// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

enum RainmakerTestsError: Error {
    ///
    /// Something could not be decoded in the expected way.
    ///
    case decodingError(URL)

    ///
    /// A static resource required for a test was not found.
    ///
    case missingFixture(URL)
}
