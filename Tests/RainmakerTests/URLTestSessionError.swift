// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Errors specific to the mock implementation of `Requesting`.
///
enum URLTestSessionError: Error {
    ///
    /// The URL request is missing the "Accept" HTTP header.
    ///
    case missingAcceptHeader

    ///
    /// A generic error that some expected information is not available.
    ///
    case missingValue

    ///
    /// The test module bundle lacks the resource at the given path.
    ///
    case resourceNotFound(String)

    ///
    /// The test module bundle apparently does not have any resources.
    ///
    case resourcesNotFound

    ///
    /// The tests require a server version for which there are no resources in the bundle.
    ///
    case serverVersionNotFound

    ///
    /// The dedicated folder for the test suite was not found.
    ///
    case suiteNotFound

    ///
    /// There is no resource folder for the specific test being run.
    ///
    case testNotFound

    ///
    /// The requested MIME type is not supported as a response.
    ///
    case unsupportedResponseType
}

extension URLTestSessionError: CustomStringConvertible {
    var description: String {
        switch self {
            case .missingAcceptHeader:
                "The URL request is missing the \"Accept\" HTTP header."
            case .missingValue:
                "An expected information is not available at this time."
            case let .resourceNotFound(path):
                "Expected resource not found: \(path)"
            case .resourcesNotFound:
                "The test module bundle apparently does not have any resources."
            case .serverVersionNotFound:
                "The tests require a server version for which there are no resources in the bundle."
            case .suiteNotFound:
                "The dedicated folder for the test suite was not found."
            case .testNotFound:
                "There is no resource folder for the specific test being run."
            case .unsupportedResponseType:
                "The requested MIME type is not supported as a response."
        }
    }
}
