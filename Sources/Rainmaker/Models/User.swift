// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A simple user description as used in file system information and returned by ``Server/currentUser()``.
///
/// ``Item/owner`` and the owners of a ``Lock`` are users, and ``Server/currentUser()`` describes the account a ``Server`` authenticates as.
///
public struct User: Model, Hashable, Identifiable {
    ///
    /// The user account identifier unique on the server.
    ///
    /// It is not necessarily the name the account logs in with, which ``Server/user`` and ``LoginResult/name`` hold, because a server can accept an email address or a login attribute of an LDAP directory as the login name.
    /// This identifier is what ``Server/userAvatar(_:size:darkTheme:)`` expects.
    ///
    public let id: String

    ///
    /// The display name of the user account.
    ///
    public let displayName: String

    ///
    /// Create a user from its parts, for example to fake one in a test or a preview.
    ///
    /// - Parameters:
    ///     - id: The user account identifier unique on the server.
    ///     - displayName: The display name of the user account.
    ///
    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
