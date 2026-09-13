// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About retrieving the avatar of a single Nextcloud user.
///
/// The fixtures backing this suite are hand-authored with synthetic, version-independent values and carried forward across versions, for the same reason ``ActivityTests`` states: what this endpoint answers depends on server state a plain baseline does not reproduce. A baseline account has no uploaded picture, so the one case that matters most here — telling a photograph the user chose from the monogram the server drew instead — cannot be provoked on one at all.
///
/// The bodies are deliberately not real images. Nothing in the library decodes them, and a fixture that carried a genuine PNG would assert only that `Data` round-trips.
///
@Suite("User Avatar") struct UserAvatarTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made — even though the route itself is a public one.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.userAvatar("admin", size: .small, darkTheme: false)
        }
    }

    @Test("Fetch", arguments: ServerVersion.allCases)
    func fetch(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let avatar = try await server.userAvatar("admin", size: .small, darkTheme: false)

        #expect(avatar.contentType == "image/png")
        #expect(avatar.data.isEmpty == false)

        // The account in this fixture uploaded a picture, which is what the header reports and what a client needs in order not to draw a monogram over it.
        #expect(avatar.isCustom)
    }

    @Test("Fetch Generated", arguments: ServerVersion.allCases)
    func fetchGenerated(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let avatar = try await server.userAvatar("guest", size: .small, darkTheme: false)

        // An account without a picture still yields an image, drawn by the server from the user's initials. That it is not the user's own choice is reported only by the header, never by the bytes.
        #expect(avatar.isCustom == false)
        #expect(avatar.contentType == "image/png")
    }

    @Test("Fetch Large Dark", arguments: ServerVersion.allCases)
    func fetchLargeDark(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let avatar = try await server.userAvatar("admin", size: .large, darkTheme: true)

        // The size reaches the path as its raw value and the dark variant as a sub-route, so this fixture is only found if both were built into the URL.
        #expect(avatar.contentType == "image/png")
        #expect(avatar.isCustom)
    }

    @Test("Fetch Unknown User", arguments: ServerVersion.allCases)
    func fetchUnknownUser(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // A user the server cannot resolve answers 404, which it also does when it declines to resolve one, so both surface the same way.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.userAvatar("nobody", size: .small, darkTheme: false)
        }
    }

    @Test("Missing Content Type", arguments: ServerVersion.allCases)
    func missingContentType(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // Without a stated type the bytes cannot be turned into an image, so the gap is reported rather than guessed at.
        await #expect(throws: RainmakerError.self) {
            _ = try await server.userAvatar("typeless", size: .small, darkTheme: false)
        }
    }

    @Test("Only Two Sizes Exist")
    func onlyTwoSizesExist() {
        // The server rounds any other requested size to one of these two and logs the request as deprecated, which is why the parameter is not an integer.
        #expect(AvatarSize.allCases.map(\.rawValue) == [64, 512])
    }
}
