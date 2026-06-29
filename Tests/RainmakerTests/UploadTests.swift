// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About uploading content to the server.
///
@Suite("Uploads") struct UploadTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        await #expect(throws: RainmakerError.credentialsRequired) {
            let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
            try await server.upload(source, to: "/", force: false)
        }
    }

    @Test("Missing Source", arguments: ServerVersion.allCases)
    func missingSource(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        await #expect(throws: RainmakerError.notFound) {
            let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
            try await server.upload(source, to: "/", force: false)
        }
    }

    @Test("File", arguments: ServerVersion.allCases)
    func file(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        let file = source.appendingCompatibility(component: "Upload.md")
        try Data("content".utf8).write(to: file)

        await #expect(throws: Never.self) {
            try await server.upload(file, to: "/", force: false)
        }
    }

    @Test("Conflict", arguments: ServerVersion.allCases)
    func conflict(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        let file = source.appendingCompatibility(component: "Readme.md")
        try Data("content".utf8).write(to: file)

        await #expect {
            try await server.upload(file, to: "/", force: false)
        } throws: { error in
            guard case RainmakerError.fileAlreadyExists = error else {
                return false
            }

            return true
        }
    }

    @Test("Overwrite File", arguments: ServerVersion.allCases)
    func overwriteFile(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        // Date the local file into the future so it is considered newer than the remote state and thus uploaded.
        let file = source.appendingCompatibility(component: "Readme.md")
        try Data("content".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date.distantFuture], ofItemAtPath: file.compatibilityPath())

        await #expect(throws: Never.self) {
            try await server.upload(file, to: "/", force: true)
        }
    }

    @Test("Overwrite Unchanged File", arguments: ServerVersion.allCases)
    func overwriteUnchangedFile(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        // Date the local file into the past so the remote state is considered up to date and no upload happens.
        let file = source.appendingCompatibility(component: "Readme.md")
        try Data("content".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file.compatibilityPath())

        await #expect(throws: Never.self) {
            try await server.upload(file, to: "/", force: true)
        }
    }

    @Test("Directory", arguments: ServerVersion.allCases)
    func directory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        try Data("example".utf8).write(to: source.appendingCompatibility(component: "Example.md"))

        let nested = source.appendingCompatibility(component: "Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("deep".utf8).write(to: nested.appendingCompatibility(component: "Deep.md"))

        await #expect(throws: Never.self) {
            try await server.upload(source, to: "/Documents", force: false)
        }
    }

    @Test("Overwrite Directory", arguments: ServerVersion.allCases)
    func overwriteDirectory(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        let source = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: source)
        }

        // Date the local file into the past so the equally named remote file is skipped while the remote orphan is deleted.
        let file = source.appendingCompatibility(component: "Example.md")
        try Data("example".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file.compatibilityPath())

        await #expect(throws: Never.self) {
            try await server.upload(source, to: "/Documents", force: true)
        }
    }
}
