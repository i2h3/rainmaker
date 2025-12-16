// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Errors specific to the mock implementation of `Requesting`.
///
enum URLTestSessionError: Error {
    ///
    /// A generic error that some expected information is not available.
    ///
    case missingValue

    ///
    /// The test module bundle lacks the given resource.
    ///
    case resourceNotFound(URL)

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
}

extension URLTestSessionError: CustomStringConvertible {
    var description: String {
        switch self {
            case .missingValue:
                "An expected information is not available at this time."
            case let .resourceNotFound(url):
                "Expected resource not found: \(url.path(percentEncoded: false))"
            case .resourcesNotFound:
                "The test module bundle apparently does not have any resources."
            case .serverVersionNotFound:
                "The tests require a server version for which there are no resources in the bundle."
            case .suiteNotFound:
                "The dedicated folder for the test suite was not found."
            case .testNotFound:
                "There is no resource folder for the specific test being run."
        }
    }
}
