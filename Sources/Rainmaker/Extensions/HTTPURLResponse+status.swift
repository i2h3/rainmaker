// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension HTTPURLResponse {
    ///
    /// Create a semantic representation based on the raw value of ``statusCode``.
    ///
    var status: HTTPStatus? {
        HTTPStatus(rawValue: self.statusCode)
    }
}
