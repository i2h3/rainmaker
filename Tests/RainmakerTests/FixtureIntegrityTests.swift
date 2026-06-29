// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// Guards structural invariants of the recorded fixtures themselves rather than the behavior of the client.
///
/// This catches mistakes a regeneration could introduce, most importantly a leaked ephemeral container port which would otherwise silently tie a fixture to the host it was recorded on.
///
@Suite("Fixture Integrity") struct FixtureIntegrityTests {
    @Test("Fixtures use the canonical host without an ephemeral port")
    func fixturesUseCanonicalHost() throws {
        let resources = try #require(Bundle.module.resourceURL)
        let root = resources.appendingCompatibility(component: "Responses")
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))

        var offenders = [String]()

        for case let url as URL in enumerator {
            // Request paths become directories in the fixture tree, so a name like "Orphan.txt" can be a directory. Only inspect regular files.
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }

            guard ["json", "xml", "txt"].contains(url.pathExtension) else {
                continue
            }

            let text = try String(contentsOf: url, encoding: .utf8)

            if text.range(of: "localhost:[0-9]", options: .regularExpression) != nil {
                offenders.append(url.compatibilityPath(percentEncoded: false))
            }
        }

        #expect(offenders.isEmpty, "Fixtures embed an ephemeral host port and must be re-recorded so the host is canonicalized: \(offenders)")
    }
}
