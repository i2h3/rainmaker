// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Semantic errors specific to this library.
///
enum RainmakerError: Error, CustomStringConvertible {
    ///
    /// The response most likely was not in the expected format or structure.
    ///
    case responseDecodingFailed(_ reason: String)

    var description: String {
        switch self {
            case let .responseDecodingFailed(reason):
                reason
        }
    }
}
