// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About listing the collectives of the authenticated user and the pages within one of them.
///
/// The fixtures backing this suite are hand-authored with synthetic, version-independent values and carried forward across versions, because recording them is not worth what it would cost: the collectives app is not part of a Nextcloud installation, and installing it on every container mounts a folder of its own into the account's files, which both changes the listings ``ListingTests`` records and makes the forced baseline reset of ``FixtureProvisioner`` treat that mount as an orphan to delete. This mirrors ``NotificationsTests`` and ``TrashTests``.
///
/// The collective is nevertheless looked up by name rather than by identifier, and the pages by their relationships rather than by position, so that the assertions stay true of a real server whose identifiers differ per deployment.
///
/// How a request is built, how an absent app and an unknown collective surface, and how the payloads decode is covered by ``CollectivesRequestTests`` instead, which drives a mock rather than the fixture tree.
///
@Suite("Collectives") struct CollectivesTests: ServerTesting {
    ///
    /// The name of the collective ``FixtureProvisioner`` seeds, which is what makes it findable without relying on an identifier.
    ///
    let seededCollective = "Cookbook"

    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.collectives()
        }
    }

    @Test("Fetch", arguments: ServerVersion.allCases)
    func fetch(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let collectives = try await server.collectives()

        // Downstream projects rely on the count to learn whether and how many collectives exist.
        #expect(collectives.isEmpty == false)

        // Looked up by name rather than by position or identifier: the identifiers the server assigns depend on the deployment.
        let collective = try #require(collectives.first { $0.name == seededCollective })

        #expect(collective.description == seededCollective)

        // The account which seeded the collective owns it, which is what makes every permission true.
        #expect(collective.level == .owner)
        #expect(collective.canEdit)
        #expect(collective.canShare)

        // Seeded without a public share, so no token is reported.
        #expect(collective.shareToken == nil)

        // A team backs every collective, and its identifier is generated per deployment, so only its presence is meaningful.
        #expect(collective.teamId.isEmpty == false)

        // The identifiers are assigned by the server and are only meaningful in being present and telling the collectives apart.
        #expect(collectives.allSatisfy { $0.id > 0 })
        #expect(Set(collectives.map(\.id)).count == collectives.count)
    }

    @Test("Fetch None", arguments: ServerVersion.allCases)
    func fetchNone(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let collectives = try await server.collectives()

        // An account which is a member of no collective at all is reported as an empty list rather than as an error, which is the primary state downstream projects check for.
        #expect(collectives.isEmpty)
    }

    @Test("Fetch Pages", arguments: ServerVersion.allCases)
    func fetchPages(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // Two requests, because there is deliberately no method combining them: the collective has to be listed before its pages can be asked for, which is exactly how a caller does it.
        let collectives = try await server.collectives()
        let collective = try #require(collectives.first { $0.name == seededCollective })
        let pages = try await server.pages(inCollective: collective.id)

        #expect(pages.isEmpty == false)

        // Every collective has exactly one page at its root, which the server creates along with it.
        let landingPages = pages.filter(\.isLandingPage)
        #expect(landingPages.count == 1)

        let landing = try #require(landingPages.first)

        // The page at the root is stored as the index file of the collective's folder, so its file name is fixed while its title is localized by the server.
        #expect(landing.fileName == "Readme.md")
        #expect(landing.filePath.isEmpty)
        #expect(landing.parentId == 0)
        #expect(landing.title.isEmpty == false)

        // The folder of the collective is not a fixed name: its first component is derived from the account's locale. Only that the server reports something usable matters, since this is what makes a page's file reachable at all.
        let collectivePath = try #require(landing.collectivePath)
        #expect(collectivePath.contains(seededCollective))

        // Every page is a Markdown file, which is what makes its size and modification date those of a file.
        #expect(pages.allSatisfy { $0.fileName.hasSuffix(".md") })
        #expect(landing.modification > Date(timeIntervalSince1970: 0))

        // The identifiers are assigned by the server and are only meaningful in being present and telling the pages apart.
        #expect(pages.allSatisfy { $0.id > 0 })
        #expect(Set(pages.map(\.id)).count == pages.count)

        // Every page other than the one at the root descends from a page in the same listing, which is what makes the hierarchy reconstructable from the flat result.
        let identifiers = Set(pages.map(\.id))
        #expect(pages.filter { $0.isLandingPage == false }.allSatisfy { identifiers.contains($0.parentId) })
    }
}
