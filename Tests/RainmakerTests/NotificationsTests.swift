// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About listing the notifications queued for the authenticated user.
///
/// The fixtures backing this suite are hand-authored with synthetic, version-independent values and carried forward across versions, because the notifications the endpoint returns depend on server state a plain baseline does not produce. This mirrors ``TrashTests``.
///
@Suite("Notifications") struct NotificationsTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.notifications()
        }
    }

    @Test("Fetch", arguments: ServerVersion.allCases)
    func fetch(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items = try await server.notifications()

        // Downstream projects rely on the count to learn whether and how many notifications are queued.
        #expect(items.isEmpty == false)
        #expect(items.count == 2)

        // The server order is preserved, newest first.
        #expect(items.map(\.id) == [1, 2])

        let first = try #require(items.first { $0.id == 1 })
        #expect(first.app == "admin_notifications")
        #expect(first.user == "admin")
        #expect(first.subject == "Hello, world!")
        #expect(first.message == "")
        #expect(first.link == "")
        #expect(first.icon == "http://localhost/apps/notifications/img/notifications-dark.svg")
        #expect(first.objectType == "admin_notifications")
        #expect(first.objectId == "1")
        #expect(first.creation == Date(timeIntervalSince1970: 1_700_000_000))

        let second = try #require(items.first { $0.id == 2 })
        #expect(second.subject == "Another notification")
        #expect(second.creation == Date(timeIntervalSince1970: 1_699_990_000))
    }

    @Test("Fetch None", arguments: ServerVersion.allCases)
    func fetchNone(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let items = try await server.notifications()

        // Zero queued notifications is the primary state downstream projects check for.
        #expect(items.isEmpty)
        #expect(items.count == 0)
    }

    @Test("Fetch With Disabled App", arguments: ServerVersion.allCases)
    func fetchWithDisabledApp(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // When the notifications app is not installed or enabled, the endpoint does not exist and a not found error surfaces.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.notifications()
        }
    }
}
