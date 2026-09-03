// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About the location a downloaded payload is staged at before it is put in place.
///
/// These tests need neither a server nor response fixtures because the location is derived from the destination alone.
///
@Suite("Download Staging Location") struct DownloadStagingLocationTests {
    ///
    /// The greatest number of bytes a single path component may have on the file systems of the supported platforms.
    ///
    private static let maximumComponentLength = 255

    @Test("Stages next to the destination")
    func stagesNextToDestination() {
        let destination = URL(fileURLWithPath: "/tmp/Downloads/Readme.md")
        let staging = destination.downloadStagingLocation()

        // Being in the same directory is what keeps putting the payload in place within one volume.
        #expect(staging.deletingLastPathComponent().compatibilityPath() == destination.deletingLastPathComponent().compatibilityPath())
    }

    @Test("Stages out of sight")
    func stagesOutOfSight() {
        let staging = URL(fileURLWithPath: "/tmp/Downloads/Readme.md").downloadStagingLocation()
        #expect(staging.lastPathComponent.hasPrefix("."))
    }

    @Test("Stages at a distinct location on every call")
    func stagesDistinctly() {
        let destination = URL(fileURLWithPath: "/tmp/Downloads/Readme.md")

        // Concurrent downloads into the same directory must not stage onto each other.
        #expect(destination.downloadStagingLocation() != destination.downloadStagingLocation())
    }

    @Test("Stays within the length limit for a destination which already exhausts it")
    func staysWithinComponentLengthLimit() {
        // A remote file may legitimately use the entire length a path component is allowed to have.
        // Embedding that name in the staged one would exceed the limit and fail the download with `ENAMETOOLONG`.
        let exhaustingName = String(repeating: "a", count: Self.maximumComponentLength - 4) + ".txt"
        #expect(exhaustingName.utf8.count == Self.maximumComponentLength)

        let staging = URL(fileURLWithPath: "/tmp/Downloads").appendingCompatibility(component: exhaustingName).downloadStagingLocation()
        #expect(staging.lastPathComponent.utf8.count <= Self.maximumComponentLength)
    }

    @Test("Stages at a fixed length regardless of the destination")
    func stagesAtFixedLength() {
        let shortDestination = URL(fileURLWithPath: "/tmp/Downloads/a")
        let longDestination = URL(fileURLWithPath: "/tmp/Downloads").appendingCompatibility(component: String(repeating: "b", count: 200))

        #expect(shortDestination.downloadStagingLocation().lastPathComponent.utf8.count == longDestination.downloadStagingLocation().lastPathComponent.utf8.count)
    }
}
