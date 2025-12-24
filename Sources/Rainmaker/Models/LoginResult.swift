// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The result of a successfully completed login flow.
///
public struct LoginResult: Model {
    ///
    /// The user name to log in with.
    ///
    public let name: String

    ///
    /// The (app) password provided by the server.
    ///
    public let password: String

    ///
    /// The final server address itself.
    ///
    public let server: URL
}
