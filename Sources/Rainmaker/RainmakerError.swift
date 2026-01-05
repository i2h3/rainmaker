// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Semantic errors specific to this library.
///
public enum RainmakerError: Error, Equatable, CustomStringConvertible {
    ///
    /// The intended action requires credentials like user name and password but they were not given.
    ///
    case credentialsRequired

    ///
    /// The response most likely was not in the expected format or structure.
    ///
    /// - Parameters:
    ///     - reason: A human readable explanation why it failed.
    ///
    case responseDecodingFailed(reason: String)

    ///
    /// The HTTP response was delivered with the given status code which was unexpected in the throwing code.
    ///
    case unexpectedStatus(code: Int)

    ///
    /// For conformance to `CustomStringConvertible` to render an error as a human readable error description.
    ///
    public var description: String {
        switch self {
            case .credentialsRequired:
                "Credentials required"
            case let .responseDecodingFailed(reason: reason):
                reason
            case let .unexpectedStatus(code: code):
                "Unexpected status: \(code) \(HTTPStatus(rawValue: code)?.description ?? "")"
        }
    }
}
