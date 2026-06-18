// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// Server capabilities related tests.
///
@Suite("Capabilities") struct CapabilitiesTests: ServerTesting {
    ///
    /// A capability the server never advertises, used to verify a lookup yields `nil`.
    ///
    struct NeverPresent: Capability {
        static let key = "no-such-capability"
        let value: String
    }

    ///
    /// A minimal capability rooted in the authenticated-only `files` object.
    ///
    struct Files: Capability {
        static let key = "files"
        let undelete: Bool?
    }

    @Test("Authenticated Fetch", arguments: ServerVersion.allCases)
    func fetchAuthenticated(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let capabilities = try await server.capabilities()

        let theming = try #require(try capabilities.get(Theming.self))
        #expect(theming.name == "Nextcloud")
        #expect(theming.productName == "Nextcloud")
        #expect(theming.color == "#00679e")
        // Verify the hyphenated keys map correctly.
        #expect(theming.colorText == "#ffffff")
        #expect(theming.backgroundPlain == false)
        #expect(theming.backgroundDefault)

        #expect(try capabilities.get(NeverPresent.self) == nil)
        #expect(capabilities.contains(Files.self))

        #expect(capabilities.version.string == serverVersion.rawValue)
        #expect(capabilities.version.major > 0)
    }

    @Test("Unauthenticated Fetch", arguments: ServerVersion.allCases)
    func fetchUnauthenticated(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)
        let capabilities = try await server.capabilities()

        // Theming is exposed to anonymous clients, the files capability is not.
        _ = try #require(try capabilities.get(Theming.self))
        #expect(capabilities.contains(Files.self) == false)

        #expect(capabilities.version.string == serverVersion.rawValue)
    }
}
