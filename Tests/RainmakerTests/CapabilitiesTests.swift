// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
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

        let trashing = try #require(try capabilities.get(Trashing.self))
        #expect(trashing.undelete == true)
        #expect(trashing.deleteFromTrash == true)

        let notifications = try #require(try capabilities.get(Notifications.self))
        #expect(notifications.ocsEndpoints?.contains("list") == true)
        #expect(notifications.push?.contains("devices") == true)
        #expect(notifications.adminNotifications == ["ocs", "cli"])
        #expect(capabilities.contains(Notifications.self))

        let activity = try #require(try capabilities.get(Activity.self))
        #expect(activity.apiV2?.contains("rich-strings") == true)
        #expect(activity.apiV2?.contains("previews") == true)
        #expect(activity.apiV2?.contains("filters-api") == true)
        #expect(capabilities.contains(Activity.self))

        // The notes app is not part of a Nextcloud installation and is installed on the recording containers on demand, which is why its capability is here at all.
        let notes = try #require(try capabilities.get(Notes.self))
        #expect(notes.apiVersion?.isEmpty == false)
        #expect(notes.version?.isEmpty == false)
        #expect(notes.notesPath?.isEmpty == false)
        #expect(capabilities.contains(Notes.self))

        #expect(capabilities.version.string == serverVersion.rawValue)
        #expect(capabilities.version.major > 0)
    }

    @Test("Unauthenticated Fetch", arguments: ServerVersion.allCases)
    func fetchUnauthenticated(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)
        let capabilities = try await server.capabilities()

        // Theming is exposed to anonymous clients, the files capability (and therefore the trash bin support) is not, and neither are the notifications and activity capabilities.
        _ = try #require(try capabilities.get(Theming.self))
        #expect(capabilities.contains(Files.self) == false)
        #expect(try capabilities.get(Trashing.self) == nil)
        #expect(try capabilities.get(Notifications.self) == nil)
        #expect(capabilities.contains(Notifications.self) == false)
        #expect(try capabilities.get(Activity.self) == nil)
        #expect(capabilities.contains(Activity.self) == false)
        #expect(try capabilities.get(Notes.self) == nil)
        #expect(capabilities.contains(Notes.self) == false)

        #expect(capabilities.version.string == serverVersion.rawValue)
    }
}
