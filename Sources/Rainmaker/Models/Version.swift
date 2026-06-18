// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The software version of a Nextcloud server as reported alongside its capabilities.
///
public struct Version: Codable, Sendable, Equatable {
    ///
    /// The major version component.
    ///
    public let major: Int

    ///
    /// The minor version component.
    ///
    public let minor: Int

    ///
    /// The micro (patch) version component.
    ///
    public let micro: Int

    ///
    /// The full version as a human readable string, e.g. `"33.0.3"`.
    ///
    public let string: String

    ///
    /// The edition of the server. Empty for the community edition.
    ///
    public let edition: String

    ///
    /// Whether this release is under extended support.
    ///
    public let extendedSupport: Bool
}
