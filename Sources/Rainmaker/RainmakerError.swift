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
    /// A move was attempted but the destination already exists and overwriting was not requested.
    ///
    case destinationExists(URL)

    ///
    /// The destination location is not an empty directory.
    ///
    case directoryNotEmpty

    ///
    /// During a local directory enumeration, the given error occurred for the item at the provided location.
    ///
    case enumeration(URL, String)

    ///
    /// A file transfer was attempted but the destination already exists and was not requested to be overwritten.
    ///
    case fileAlreadyExists(URL)

    ///
    /// Whatever you were looking for is not there.
    ///
    case notFound

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
            case let .destinationExists(url):
                "A remote item already exists at: \(url.compatibilityPath())"
            case .directoryNotEmpty:
                "The destination location is not an empty directory."
            case let .enumeration(url, error):
                "The item at \(url.compatibilityPath()) could not be enumerated: \(error)"
            case let .fileAlreadyExists(url):
                "A file already exists at: \(url.compatibilityPath())"
            case .notFound:
                "Not found."
            case let .responseDecodingFailed(reason: reason):
                reason
            case let .unexpectedStatus(code: code):
                "Unexpected status: \(code) \(HTTPStatus(rawValue: code)?.description ?? "")"
        }
    }
}
