// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About telling releases of the notes app apart through the ``Notes`` capability.
///
/// The behaviours ``Notes/storesAttachmentsPerNote`` and ``Notes/supportsAttachmentDeletion`` describe are not announced through the notes API version, so they rest on comparing ``Notes/version`` against ``Notes/attachmentFoldersAppVersion``. These tests need neither a server nor response fixtures because the comparison is a pure function of the two strings.
///
@Suite("Notes Capability Version") struct NotesCapabilityVersionTests {
    ///
    /// Decode the notes capability from the object a server advertises under the `notes` key.
    ///
    private func capability(_ json: String) throws -> Notes {
        try JSONDecoder().decode(Notes.self, from: Data(json.utf8))
    }

    @Test("Compares Versions Component By Component As Numbers")
    func numericComparison() {
        #expect(Notes.compareAppVersions("6.1.0", "6.1.0") == .orderedSame)
        #expect(Notes.compareAppVersions("6.0.2", "6.1.0") == .orderedAscending)
        #expect(Notes.compareAppVersions("6.1.1", "6.1.0") == .orderedDescending)

        // A lexical comparison would get this one wrong.
        #expect(Notes.compareAppVersions("6.10.0", "6.9.0") == .orderedDescending)

        // Missing components count as zero.
        #expect(Notes.compareAppVersions("7", "6.1.0") == .orderedDescending)
        #expect(Notes.compareAppVersions("6.1", "6.1.0") == .orderedSame)
    }

    @Test("Orders A Pre-Release Before Its Release")
    func preRelease() {
        // The attachment deletion arrived during the pre-releases of 6.1.0, so treating any of them as 6.1.0 could promise a feature which is not there.
        #expect(Notes.compareAppVersions("6.1.0-beta.3", "6.1.0") == .orderedAscending)
        #expect(Notes.compareAppVersions("6.1.0", "6.1.0-beta.3") == .orderedDescending)
        #expect(Notes.compareAppVersions("6.1.1-beta.1", "6.1.0") == .orderedDescending)

        // Build metadata is no pre-release and is ignored.
        #expect(Notes.compareAppVersions("6.1.0+build.7", "6.1.0") == .orderedSame)
    }

    @Test("Refuses To Compare What It Cannot Read")
    func unreadable() {
        #expect(Notes.compareAppVersions("", "6.1.0") == nil)
        #expect(Notes.compareAppVersions("garbage", "6.1.0") == nil)
        #expect(Notes.compareAppVersions("6.x.0", "6.1.0") == nil)
        #expect(Notes.compareAppVersions("6..0", "6.1.0") == nil)
        #expect(Notes.compareAppVersions("6.1.0", "latest") == nil)
    }

    @Test("Checks The Advertised Version Against A Minimum")
    func atLeast() throws {
        let current = try capability(#"{"api_version":["0.2","1.3","1.4"],"version":"6.1.0","notes_path":"Notes"}"#)
        #expect(current.isAppVersion(atLeast: "6.1.0"))
        #expect(current.isAppVersion(atLeast: "6.0.2"))
        #expect(current.isAppVersion(atLeast: "6.1.1") == false)

        // Without a version, or with one which cannot be read, the answer is no rather than a guess.
        let unversioned = try capability(#"{"api_version":["0.2","1.3","1.4"]}"#)
        #expect(unversioned.isAppVersion(atLeast: "1.0.0") == false)

        let garbled = try capability(#"{"api_version":["0.2","1.3","1.4"],"version":"next"}"#)
        #expect(garbled.isAppVersion(atLeast: "1.0.0") == false)

        // An unreadable minimum is not met either.
        #expect(current.isAppVersion(atLeast: "soon") == false)
    }

    @Test("Attachment Behaviours Follow The App Version")
    func attachmentBehaviours() throws {
        // What the recording containers of Nextcloud 33 and newer advertise.
        let current = try capability(#"{"api_version":["0.2","1.3","1.4"],"version":"6.1.0","notes_path":"Notizen"}"#)
        #expect(current.storesAttachmentsPerNote)
        #expect(current.supportsAttachmentDeletion)

        // What the recording containers of Nextcloud 31 and 32 advertise. The API version is the same, which is why the app version has to decide.
        let older = try capability(#"{"api_version":["0.2","1.3","1.4"],"version":"5.0.2","notes_path":"Notizen"}"#)
        #expect(older.isSupported)
        #expect(older.storesAttachmentsPerNote == false)
        #expect(older.supportsAttachmentDeletion == false)

        let preRelease = try capability(#"{"api_version":["0.2","1.3","1.4"],"version":"6.1.0-beta.3"}"#)
        #expect(preRelease.supportsAttachmentDeletion == false)

        let unversioned = try capability(#"{"api_version":["0.2","1.3","1.4"]}"#)
        #expect(unversioned.storesAttachmentsPerNote == false)
        #expect(unversioned.supportsAttachmentDeletion == false)
    }
}
