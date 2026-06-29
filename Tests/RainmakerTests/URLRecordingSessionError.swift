// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Errors specific to the recording implementation of `Requesting`.
///
/// These mirror the failure modes of ``URLTestSession`` but occur while capturing live responses into fixtures rather than replaying them.
///
enum URLRecordingSessionError: Error, CustomStringConvertible {
    ///
    /// A value expected on the request or response, such as the HTTP method or URL, is not available.
    ///
    case missingValue

    ///
    /// The live response was not an `HTTPURLResponse` and therefore cannot be recorded.
    ///
    case unexpectedResponseType

    ///
    /// A fixture file could not be written to the given path.
    ///
    case writeFailed(String)

    var description: String {
        switch self {
            case .missingValue:
                "An expected value on the request or response is not available."
            case .unexpectedResponseType:
                "The live response was not an HTTPURLResponse and cannot be recorded."
            case let .writeFailed(path):
                "Failed to write a fixture file at: \(path)"
        }
    }
}
