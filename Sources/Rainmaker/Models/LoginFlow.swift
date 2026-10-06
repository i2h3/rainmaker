// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// All the necessary information to begin and monitor a client login flow.
///
/// ``Server/login()`` begins a flow and returns this, and ``Server/poll(_:)`` takes it to check whether the user completed the flow, which yields a ``LoginResult``.
/// A client which keeps a flow across launches, or a test which fakes one, creates it through ``init(endpoint:entry:token:)``.
///
public struct LoginFlow: Model, Hashable {
    ///
    /// The endpoint to poll for the status, which ``Server/poll(_:)`` sends ``token`` to.
    ///
    public let endpoint: URL

    ///
    /// The initial web page to present to the user for logging in.
    ///
    /// ``Server/poll(_:)`` does not use it.
    ///
    public let entry: URL

    ///
    /// The token the specific login flow is identified by, which ``Server/poll(_:)`` sends to ``endpoint``.
    ///
    /// It is a secret: whoever knows it can fetch the ``LoginResult`` once the user completed the flow.
    ///
    public let token: String

    ///
    /// Create a login flow from its parts, for example to poll a flow begun earlier through ``Server/poll(_:)``.
    ///
    /// - Parameters:
    ///     - endpoint: The endpoint to poll for the status.
    ///     - entry: The initial web page to present to the user for logging in.
    ///     - token: The token the specific login flow is identified by.
    ///
    public init(endpoint: URL, entry: URL, token: String) {
        self.endpoint = endpoint
        self.entry = entry
        self.token = token
    }
}
