// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Amount of available bytes in the folder.
///
public enum AvailableQuota: Model, Hashable {
    ///
    /// A defined number of bytes left available.
    ///
    case limited(Int64)

    ///
    /// Equals the raw representation as `-1`.
    ///
    case uncomputed

    ///
    /// Equals the raw representation as `-2`.
    ///
    case unknown

    ///
    /// Equals the raw representation as `-3`.
    ///
    case unlimited

    ///
    /// Derive a case based on the raw value returned by the server.
    ///
    /// Note that some values are magic numbers with special semantics as documented by the cases of this enum.
    ///
    public init(_ rawValue: Int64) {
        switch rawValue {
            case -1:
                self = .uncomputed
            case -2:
                self = .unknown
            case -3:
                self = .unlimited
            default:
                self = .limited(rawValue)
        }
    }

    ///
    /// Encode the named cases as readable strings and the value-carrying case as the plain number of bytes.
    ///
    /// The magic numbers the server uses for the named cases are therefore not reproduced in the encoded form, which is meant to be read rather than sent back to a server.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
            case let .limited(bytes):
                try container.encode(bytes)
            case .uncomputed:
                try container.encode("uncomputed")
            case .unknown:
                try container.encode("unknown")
            case .unlimited:
                try container.encode("unlimited")
        }
    }
}
