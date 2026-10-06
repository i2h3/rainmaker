// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The result of a successfully completed login flow.
///
/// ``Server/poll(_:)`` returns this once the user granted access to the ``LoginFlow`` it was given.
/// Its ``name`` and ``password`` are what a ``Server`` authenticating as that account is created with, at the address ``server``.
///
public struct LoginResult: Model, Hashable {
    ///
    /// The login name to authenticate with together with ``password``.
    ///
    /// This is the name the user logged in with in the browser, which can differ from the identifier of the account, for example when the server accepts an email address or a login attribute of an LDAP directory.
    /// The identifier of the account, not this name, is what the server keys the WebDAV paths and the avatar of the account by.
    ///
    public let name: String

    ///
    /// The app password the server created for this client, which is what a ``Server`` authenticates with instead of the user's own password.
    ///
    /// ``Server/deleteAppPassword()`` revokes it again.
    ///
    public let password: String

    ///
    /// The address of the server the flow was completed on, as the server derives it from the browser's request and its own configuration.
    ///
    /// It can differ from the address ``Server/login()`` was called on, for example when the browser reached the server under another host name or the server is configured to overwrite its host or protocol.
    ///
    public let server: URL

    ///
    /// Create a login result from its parts, for example to fake one in a test or a preview.
    ///
    /// - Parameters:
    ///     - name: The login name to authenticate with.
    ///     - password: The app password the server created.
    ///     - server: The address of the server the flow was completed on.
    ///
    public init(name: String, password: String, server: URL) {
        self.name = name
        self.password = password
        self.server = server
    }
}
