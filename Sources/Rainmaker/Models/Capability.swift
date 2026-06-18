// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A feature a Nextcloud server may or may not advertise in its capabilities response.
///
/// This protocol is the extension point for third parties: downstream projects can define their own capability types and query them through a ``CapabilitySet`` exactly like the built-in ones.
///
/// A conforming type only needs to model the fields it cares about and declare the ``key`` under which the server advertises it.
/// Any other fields in the server's capability object are ignored by the synthesized `Decodable` conformance.
/// For example:
///
/// ```swift
/// struct Trash: Capability {
///     static let key = "files"
///     let undelete: Bool?
/// }
/// ```
///
public protocol Capability: Decodable, Sendable {
    ///
    /// The key under which this capability is advertised in the server's `capabilities` object.
    ///
    static var key: String { get }
}
