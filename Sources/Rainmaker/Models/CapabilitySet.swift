// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The capabilities advertised by a Nextcloud server.
///
/// This is a container for the raw capabilities data: the open-ended `capabilities` object is kept as raw JSON bytes and individual capabilities are parsed on demand through ``get(_:)``.
/// That is what makes the API extensible for third parties — see ``Capability``.
///
/// The set of advertised capabilities differs between authenticated and unauthenticated requests, so the result depends on whether the ``Server`` was created with credentials.
///
public struct CapabilitySet: Sendable {
    ///
    /// The software version of the server reported alongside the capabilities.
    ///
    public let version: Version

    ///
    /// The raw JSON bytes of the server's `capabilities` object, parsed on demand by ``get(_:)``.
    ///
    public let raw: Data

    ///
    /// Create a capability set from a server version and the raw capabilities object.
    ///
    /// - Parameters:
    ///     - version: The reported server software version.
    ///     - raw: The raw JSON bytes of the `capabilities` object.
    ///
    public init(version: Version, raw: Data) {
        self.version = version
        self.raw = raw
    }

    ///
    /// Retrieve a specific capability if the server advertises it.
    ///
    /// Pass the ``Capability`` type to look up, for example `get(Theming.self)`.
    ///
    /// - Returns: The parsed capability, or `nil` if the server does not advertise it.
    ///
    /// - Throws: A `DecodingError` if the capability is advertised but cannot be parsed into the requested type.
    ///
    public func get<C: Capability>(_: C.Type) throws -> C? {
        try JSONDecoder().decode(Lookup<C>.self, from: raw).value
    }

    ///
    /// Whether the server advertises the given capability, without parsing it.
    ///
    /// Pass the ``Capability`` type to check for.
    ///
    /// - Returns: `true` if advertised, otherwise `false`.
    ///
    public func contains<C: Capability>(_: C.Type) -> Bool {
        guard let keys = try? JSONDecoder().decode(TopLevelKeys.self, from: raw) else {
            return false
        }

        return keys.names.contains(C.key)
    }
}

// MARK: - Decoding Helpers

///
/// A coding key whose name is only known at run time, used to navigate the dynamic capabilities object.
///
private struct DynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

///
/// Decodes a single ``Capability`` out of the capabilities object, yielding `nil` when its key is absent.
///
private struct Lookup<C: Capability>: Decodable {
    let value: C?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        guard let key = DynamicKey(stringValue: C.key), container.contains(key) else {
            value = nil
            return
        }

        value = try container.decode(C.self, forKey: key)
    }
}

///
/// Collects the top-level keys of the capabilities object for cheap presence checks.
///
private struct TopLevelKeys: Decodable {
    let names: Set<String>

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        names = Set(container.allKeys.map(\.stringValue))
    }
}
