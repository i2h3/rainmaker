// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A simple user description as used in file system information.
///
public struct User: Model, Identifiable {
    ///
    /// The user account identifier unique on the server.
    ///
    public let id: String

    ///
    /// The display name of the user account.
    ///
    public let displayName: String
}
