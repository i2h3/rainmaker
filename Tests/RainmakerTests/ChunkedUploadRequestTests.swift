// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how ``Server/upload(_:to:force:chunkSize:)`` splits a large file into chunks and drives the server's chunked upload protocol with them.
///
/// These tests deliberately do not use the fixture tree: ``FixtureLocator`` keys fixtures by HTTP method and URL path only and ``URLTestSession`` never looks at the bytes of an upload, so a replayed test can neither prove that a file was split correctly nor that the headers a server needs were sent. A capturing ``MockRequesting`` is used instead, which also makes it possible to answer the way a live baseline cannot be made to, such as with a transfer folder left behind by an earlier attempt or with an exhausted quota.
///
@Suite("Chunked Upload Requests") struct ChunkedUploadRequestTests {
    ///
    /// Counts occurrences across the calls of a responder, which is a `Sendable` closure and therefore cannot mutate a captured variable itself.
    ///
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        ///
        /// Increment the count and return the new value.
        ///
        func next() -> Int {
            lock.lock()

            defer {
                lock.unlock()
            }

            count += 1
            return count
        }
    }

    ///
    /// A local test file together with the directory it lives in and the bytes it holds.
    ///
    private struct TestFile {
        let url: URL
        let directory: URL
        let content: Data
    }

    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// The modification date every test file is pinned to, so that the name of the transfer folder is known in advance.
    ///
    let modification = Date(timeIntervalSince1970: 1_700_000_000)

    ///
    /// Answer the way a plain server answers the chunked upload of a new file: the destination does not exist yet, and every step succeeds.
    ///
    static func defaultAnswer(for request: URLRequest) -> (body: Data, statusCode: Int, headerFields: [String: String]?) {
        switch request.httpMethod {
            case "PROPFIND":
                (Data(), 404, nil)
            case "MKCOL", "PUT", "MOVE":
                (Data(), 201, nil)
            case "DELETE":
                (Data(), 204, nil)
            default:
                (Data(), 500, nil)
        }
    }

    ///
    /// Build a server whose session is the given mock.
    ///
    private func makeServer(session: MockRequesting) -> Server {
        Server(address: serverAddress, password: "admin", user: "admin", session: session, userAgent: "RainmakerTests")
    }

    ///
    /// Write a file of the given size whose bytes follow a pattern, so that a reassembly can be checked byte for byte, and pin its modification date.
    ///
    private func makeFile(named name: String, size: Int) throws -> TestFile {
        let directory = FileManager.default.temporaryDirectory.appendingCompatibility(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var content = Data(count: size)

        content.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            for index in 0 ..< size {
                buffer[index] = UInt8(truncatingIfNeeded: (index &* 31) &+ (index >> 12))
            }
        }

        let url = directory.appendingCompatibility(component: name)
        try content.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modification], ofItemAtPath: url.compatibilityPath())

        return TestFile(url: url, directory: directory, content: content)
    }

    ///
    /// The decoded path of a captured request.
    ///
    private func path(of request: URLRequest) -> String? {
        request.url?.compatibilityPath(percentEncoded: false)
    }

    // MARK: - Splitting

    @Test("Large File Is Sent In Chunks")
    func chunkedSequence() async throws {
        let size = 2 * Server.minimumChunkSize + 1
        let file = try makeFile(named: "Large.bin", size: size)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        let session = MockRequesting(responder: Self.defaultAnswer)
        let server = makeServer(session: session)
        try await server.upload(file.url, to: "/Documents", force: false, chunkSize: Server.minimumChunkSize)

        let requests = session.requests
        let transfer = "/remote.php/dav/uploads/admin/" + Server.uploadTransferName(for: "/Documents/Large.bin", size: Int64(size), modification: modification)
        let destination = server.webDAVAddress.appendingCompatibility(path: "/Documents/Large.bin").absoluteString

        #expect(requests.map(\.httpMethod) == ["PROPFIND", "MKCOL", "PUT", "PUT", "PUT", "MOVE"])
        #expect(path(of: requests[0]) == "/remote.php/dav/files/admin/Documents/Large.bin")
        #expect(path(of: requests[1]) == transfer)
        #expect(path(of: requests[2]) == transfer + "/1")
        #expect(path(of: requests[3]) == transfer + "/2")
        #expect(path(of: requests[4]) == transfer + "/3")
        #expect(path(of: requests[5]) == transfer + "/.file")

        // Every request of the transfer names the destination, which is where a server backed by an object storage streams the chunks to, and every chunk and the final move name the total size, which the server checks the assembled file against.
        for request in requests[1...] {
            #expect(request.value(forHTTPHeaderField: "Destination") == destination)
        }

        for request in requests[2...] {
            #expect(request.value(forHTTPHeaderField: "OC-Total-Length") == String(size))
        }

        for request in requests[2 ... 4] {
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        }

        // The chunks are the file, in order and without a byte missing or repeated, with only the last one shorter than the chunk size.
        let chunks = requests[2 ... 4].compactMap(\.httpBody)
        #expect(chunks.map(\.count) == [Server.minimumChunkSize, Server.minimumChunkSize, 1])
        #expect(chunks.reduce(Data(), +) == file.content)

        // Assembling carries the modification date the way a single request does, and asks the server to replace whatever the destination holds.
        #expect(requests[5].value(forHTTPHeaderField: "X-OC-Mtime") == "1700000000")
        #expect(requests[5].value(forHTTPHeaderField: "Overwrite") == "T")
    }

    @Test("Small File Is Sent In One Request")
    func smallFile() async throws {
        let file = try makeFile(named: "Small.bin", size: 4096)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        let session = MockRequesting(responder: Self.defaultAnswer)
        try await makeServer(session: session).upload(file.url, to: "/", force: false, chunkSize: Server.defaultChunkSize)

        let requests = session.requests
        #expect(requests.map(\.httpMethod) == ["PROPFIND", "PUT"])
        #expect(path(of: requests[1]) == "/remote.php/dav/files/admin/Small.bin")
        #expect(requests[1].value(forHTTPHeaderField: "Destination") == nil)
        #expect(requests[1].httpBody == file.content)
    }

    @Test("File Of Exactly The Chunk Size Is Sent In One Request")
    func fileOfChunkSize() async throws {
        let file = try makeFile(named: "Exact.bin", size: Server.minimumChunkSize)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        let session = MockRequesting(responder: Self.defaultAnswer)
        try await makeServer(session: session).upload(file.url, to: "/", force: false, chunkSize: Server.minimumChunkSize)

        #expect(session.requests.map(\.httpMethod) == ["PROPFIND", "PUT"])
    }

    @Test("Chunk Size Below The Minimum Is Raised")
    func minimumChunkSize() async throws {
        let file = try makeFile(named: "Large.bin", size: Server.minimumChunkSize + 4096)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        let session = MockRequesting(responder: Self.defaultAnswer)
        try await makeServer(session: session).upload(file.url, to: "/", force: false, chunkSize: 1)

        // Two chunks rather than millions: the requested size is raised to the smallest one an object storage accepts.
        let requests = session.requests
        #expect(requests.map(\.httpMethod) == ["PROPFIND", "MKCOL", "PUT", "PUT", "MOVE"])
        #expect(requests[2].httpBody?.count == Server.minimumChunkSize)
        #expect(requests[3].httpBody?.count == 4096)
    }

    @Test("Chunk Size Grows With Very Large Files")
    func chunkCountLimit() {
        let hundredGibibytes: Int64 = 100 * 1024 * 1024 * 1024

        // Ten thousand chunks of the default size fall just short of 100 GiB, so a file of that size needs slightly larger chunks to fit.
        #expect(Server.effectiveChunkSize(for: hundredGibibytes, requested: Server.defaultChunkSize) == 10_737_419)
        #expect(Server.effectiveChunkSize(for: 1, requested: Server.defaultChunkSize) == Int64(Server.defaultChunkSize))
        #expect(Server.effectiveChunkSize(for: 1, requested: 1) == Int64(Server.minimumChunkSize))
        #expect(Server.effectiveChunkSize(for: 1, requested: 3 * Server.defaultChunkSize) == Int64(3 * Server.defaultChunkSize))
    }

    // MARK: - Transfer Folder

    @Test("Transfer Folder Name Is Deterministic")
    func transferName() {
        let name = Server.uploadTransferName(for: "/Documents/Large.bin", size: 42, modification: modification)

        #expect(name.count == 32)
        #expect(name.allSatisfy { $0.isHexDigit && $0.isUppercase == false })
        #expect(Server.uploadTransferName(for: "/Documents/Large.bin", size: 42, modification: modification) == name)

        // Any change to the file or its destination names a different folder, so chunks of different versions never meet.
        #expect(Server.uploadTransferName(for: "/Documents/Large.bin", size: 43, modification: modification) != name)
        #expect(Server.uploadTransferName(for: "/Documents/Large.bin", size: 42, modification: nil) != name)
        #expect(Server.uploadTransferName(for: "/Documents/Other.bin", size: 42, modification: modification) != name)
    }

    @Test("Leftover Transfer Folder Is Replaced")
    func existingTransfer() async throws {
        let file = try makeFile(named: "Large.bin", size: Server.minimumChunkSize + 1)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        // The first attempt to create the folder finds one left behind by an interrupted upload.
        let creations = Counter()
        let session = MockRequesting { request in
            if request.httpMethod == "MKCOL", creations.next() == 1 {
                return (Data(), 405, nil)
            }

            return Self.defaultAnswer(for: request)
        }

        try await makeServer(session: session).upload(file.url, to: "/", force: false, chunkSize: Server.minimumChunkSize)

        let requests = session.requests
        #expect(requests.map(\.httpMethod) == ["PROPFIND", "MKCOL", "DELETE", "MKCOL", "PUT", "PUT", "MOVE"])

        // It is the leftover folder which is removed, not the destination.
        #expect(requests[2].url == requests[1].url)
        #expect(requests[3].url == requests[1].url)
    }

    // MARK: - Failures

    @Test("Failed Chunk Removes The Transfer")
    func failedChunk() async throws {
        let file = try makeFile(named: "Large.bin", size: 2 * Server.minimumChunkSize + 1)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        // The account runs out of quota on the second chunk.
        let session = MockRequesting { request in
            if request.httpMethod == "PUT", request.url?.lastPathComponent == "2" {
                return (Data(), 507, nil)
            }

            return Self.defaultAnswer(for: request)
        }

        await #expect(throws: RainmakerError.unexpectedStatus(code: 507)) {
            try await makeServer(session: session).upload(file.url, to: "/", force: false, chunkSize: Server.minimumChunkSize)
        }

        // Nothing is assembled, and the folder is removed rather than left to occupy the quota until the server expires it.
        let requests = session.requests
        #expect(requests.map(\.httpMethod) == ["PROPFIND", "MKCOL", "PUT", "PUT", "DELETE"])
        #expect(requests.last?.url == requests[1].url)
    }

    @Test("Changed Source Is Not Assembled")
    func changedSource() async throws {
        let file = try makeFile(named: "Large.bin", size: 2 * Server.minimumChunkSize + 1)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        // The file grows while its first chunk is on the wire.
        let source = file.url
        let session = MockRequesting { request in
            if request.httpMethod == "PUT", request.url?.lastPathComponent == "1", let handle = try? FileHandle(forWritingTo: source) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data([0]))
                try? handle.close()
            }

            return Self.defaultAnswer(for: request)
        }

        await #expect(throws: RainmakerError.sourceChanged(file.url)) {
            try await makeServer(session: session).upload(file.url, to: "/", force: false, chunkSize: Server.minimumChunkSize)
        }

        // Every chunk of the original size is sent, but the server is never asked to assemble them.
        let requests = session.requests
        #expect(requests.map(\.httpMethod) == ["PROPFIND", "MKCOL", "PUT", "PUT", "PUT", "DELETE"])
    }

    @Test("Missing Destination Directory Surfaces As Not Found")
    func missingParent() async throws {
        let file = try makeFile(named: "Large.bin", size: Server.minimumChunkSize + 1)

        defer {
            try? FileManager.default.removeItem(at: file.directory)
        }

        // Assembling into a directory which does not exist is answered with a conflict, exactly as a single request is.
        let session = MockRequesting { request in
            if request.httpMethod == "MOVE" {
                return (Data(), 409, nil)
            }

            return Self.defaultAnswer(for: request)
        }

        await #expect(throws: RainmakerError.notFound) {
            try await makeServer(session: session).upload(file.url, to: "/Missing", force: false, chunkSize: Server.minimumChunkSize)
        }

        #expect(session.requests.map(\.httpMethod) == ["PROPFIND", "MKCOL", "PUT", "PUT", "MOVE", "DELETE"])
    }
}
