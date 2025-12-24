// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// All the necessary information to begin and monitor a client login flow.
///
public struct LoginFlow: Model {
    ///
    /// The endpoint to poll for the status.
    ///
    public let endpoint: URL

    ///
    /// The initial web page to present to the user for logging in.
    ///
    public let entry: URL

    ///
    /// The token the specific login flow is identified by.
    ///
    public let token: String
}
