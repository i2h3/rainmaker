// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server.
///
/// This is a data transfer object and is converted to a ``LoginFlow`` for external callers.
///
struct LoginFlowResponse: Decodable {
    struct Poll: Decodable {
        let endpoint: URL
        let token: String
    }

    let login: URL
    let poll: Poll
}
