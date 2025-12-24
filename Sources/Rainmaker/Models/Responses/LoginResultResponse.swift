// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server.
///
/// This is a data transfer object and is converted to a ``LoginResult`` for external callers.
///
struct LoginResultResponse: Decodable {
    let loginName: String
    let appPassword: String
    let server: URL
}
