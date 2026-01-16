// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About downloading content from the server.
///
@Suite("Downloads") struct DownloadTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            let destination = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
            try await server.download("/Readme.md", to: destination, force: false)
        }
    }

    @Test("File", arguments: ServerVersion.allCases)
    func file(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let destination = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        try await server.download("/Readme.md", to: destination, force: false)

        let downloadedFile = destination.appending(component: "Readme.md")
        #expect(FileManager.default.fileExists(atPath: downloadedFile.path()))

        let content = try Data(contentsOf: downloadedFile)
        #expect(content.isEmpty == false)
    }

    @Test("Directory", arguments: ServerVersion.allCases)
    func directory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let destination = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        try await server.download("/Documents", to: destination, force: false)

        let downloadedFile = destination.appending(component: "Example.md")
        #expect(FileManager.default.fileExists(atPath: downloadedFile.path()))

        let content = try Data(contentsOf: downloadedFile)
        #expect(content.isEmpty == false)
    }

    @Test("Overwrite File", arguments: ServerVersion.allCases)
    func overwriteFile(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let destination = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        // Pre-create an old version of the file with a very old modification date.
        let existingFile = destination.appending(component: "Readme.md")
        let oldContent = Data("old content".utf8)
        try oldContent.write(to: existingFile)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: existingFile.path())

        try await server.download("/Readme.md", to: destination, force: true)

        let newContent = try Data(contentsOf: existingFile)
        #expect(newContent != oldContent)
    }

    @Test("Overwrite Unchanged File", arguments: ServerVersion.allCases)
    func overwriteUnchangedFile(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let destination = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        // Pre-create a file with a modification date far in the future so it is always considered up to date.
        let existingFile = destination.appending(component: "Readme.md")
        let originalContent = Data("original content".utf8)
        try originalContent.write(to: existingFile)
        try FileManager.default.setAttributes([.modificationDate: Date.distantFuture], ofItemAtPath: existingFile.path())

        try await server.download("/Readme.md", to: destination, force: true)

        // The file should not have been re-downloaded because the local copy is not older.
        let currentContent = try Data(contentsOf: existingFile)
        #expect(currentContent == originalContent)
    }

    @Test("Overwrite Directory", arguments: ServerVersion.allCases)
    func overwriteDirectory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let destination = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        // Pre-create an orphan file that should be deleted during synchronization.
        let orphanFile = destination.appending(component: "Orphan.txt")
        try Data("orphan".utf8).write(to: orphanFile)

        try await server.download("/Documents", to: destination, force: true)

        // The orphan file should have been deleted.
        #expect(FileManager.default.fileExists(atPath: orphanFile.path()) == false)

        // The remote file should have been downloaded.
        let downloadedFile = destination.appending(component: "Example.md")
        #expect(FileManager.default.fileExists(atPath: downloadedFile.path()))
    }

    @Test("Overwrite Directory Preserves Existing Remote Items", arguments: ServerVersion.allCases)
    func overwriteDirectoryPreservesExistingRemoteItems(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // Construct the destination URL the same way `RainmakerCLI` does, so the test exercises the
        // production path including the trailing slash that `.isDirectory` adds to `path(...)`.
        let destination = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        // Pre-create the file that also exists on the remote, simulating a prior successful download.
        let existingFile = destination.appending(component: "Example.md")
        try Data("pre-existing".utf8).write(to: existingFile)

        try await server.download("/Documents", to: destination, force: true)

        // The file should still exist after synchronization because it is present in the remote state.
        #expect(FileManager.default.fileExists(atPath: existingFile.path(percentEncoded: false)))
    }
}
