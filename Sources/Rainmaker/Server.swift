// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// Main type to interact with an account on a Nextcloud server.
///
public final class Server {
    static let resourceURL = Bundle.module.resourceURL!

    nonisolated(unsafe) let fileManager = FileManager.default
    let logger = Logger(category: "Server")
    let jsonDecoder: JSONDecoder
    let session: any Requesting

    ///
    /// HTTP address of the Nextcloud host.
    ///
    public let address: URL

    ///
    /// In most cases, this is the app password and not the account password.
    ///
    public let password: String?

    ///
    /// The Nextcloud user name used to identify as.
    ///
    public let user: String?

    ///
    /// The user agent to report as in HTTP request headers.
    ///
    public let userAgent: String

    ///
    /// The path prefix appended to the base address before the actual remote subject path on every WebDAV request, including the user's name.
    ///
    /// Looks like `"/remote.php/dav/files/<user>"`.
    ///
    public let webDAVPathPrefix: String

    ///
    /// WebDAV root address for the account on the server.
    ///
    public let webDAVAddress: URL

    // MARK: - Helpers

    ///
    /// Helper method which ensures this object was setup up with a user name and password.
    ///
    /// - Throws: If this is called and the ``user`` or ``password`` are not defined.
    ///
    private func requireCredentials() throws {
        guard user != nil, password != nil else {
            throw RainmakerError.credentialsRequired
        }
    }

    ///
    /// List the content of the remote directory.
    ///
    private func content(at path: String, depth: UInt = 1) async throws -> [Item] {
        let url = webDAVAddress.appending(path: path, directoryHint: .inferFromPath)
        var request = try makeWebDAVRequest(for: url, method: .propfind)
        request.httpBody = try? Data(contentsOf: Self.resourceURL.appending(component: "Bodies").appending(component: "Listing.xml"))
        request.setValue("\(depth)", forHTTPHeaderField: "Depth")

        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .multiStatus else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let allItems = try ResponseParser.items(from: data, webDAVPathPrefix: webDAVPathPrefix)

        // When fetching metadata about a specific item (depth 0), return the item itself.
        // When listing directory contents (depth > 0), filter out the listed directory itself.
        if depth == 0 {
            return allItems
        }

        let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path

        return allItems.filter { item in
            let normalizedItemPath = item.path.hasSuffix("/") ? String(item.path.dropLast()) : item.path
            return normalizedPath != normalizedItemPath
        }
    }

    ///
    /// Normalize a path so that it can be used as a key for matching local and remote items.
    ///
    /// Strips surrounding slashes so that `"/Foo/"`, `"Foo/"`, `"/Foo"`, and `"Foo"` all collapse to `"Foo"`.
    ///
    private func normalizeKey(_ path: String) -> String {
        var slice = Substring(path)

        while slice.hasPrefix("/") {
            slice = slice.dropFirst()
        }

        while slice.hasSuffix("/") {
            slice = slice.dropLast()
        }

        return String(slice)
    }

    ///
    /// Enumerate local files recursively and return a dictionary mapping normalized relative paths to their URLs.
    ///
    private func enumerateLocalFiles(at destination: URL) throws -> [String: URL] {
        logger.debug("Enumerating local files at \"\(destination.path(percentEncoded: false))\"...")

        var enumerationErrorItem: URL?
        var enumerationError: (any Error)?

        let localEnumerator = fileManager.enumerator(at: destination, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) { url, error in
            enumerationErrorItem = url
            enumerationError = error
            return false
        }

        var result = [String: URL]()
        // Use path components rather than string-prefix arithmetic so that resolving symlinks (e.g. macOS' `/var` → `/private/var`)
        // or other inconsistencies between the supplied destination URL and the URLs yielded by the enumerator do not skew the relative path.
        let destinationComponents = destination.resolvingSymlinksInPath().pathComponents

        if let localEnumerator {
            for case let fileURL as URL in localEnumerator {
                let fileComponents = fileURL.resolvingSymlinksInPath().pathComponents

                guard fileComponents.count > destinationComponents.count else {
                    continue
                }

                let relativeComponents = fileComponents.dropFirst(destinationComponents.count)
                let relativePath = relativeComponents.joined(separator: "/")
                let normalizedKey = normalizeKey(relativePath)
                result[normalizedKey] = fileURL
                logger.debug("Found \"\(normalizedKey)\"")
            }
        }

        // The error handler closure is invoked during iteration, so the check must come after the loop.
        if let enumerationErrorItem, let enumerationError {
            throw RainmakerError.enumeration(enumerationErrorItem, enumerationError.localizedDescription)
        }

        return result
    }

    private func downloadDirectory(_ source: String, to destination: URL, force: Bool) async throws {
        logger.debug("Downloading directory from \"\(source)\" to \"\(destination.path(percentEncoded: false))\" \(force ? "with" : "without") force...")

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) == false {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        let destinationDirectoryContents = try fileManager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)

        if force == false, destinationDirectoryContents.isEmpty == false {
            throw RainmakerError.directoryNotEmpty
        }

        // Enumerate local state recursively.

        let localItemsByRelativePath = try enumerateLocalFiles(at: destination)

        // Enumerate remote state recursively.

        let normalizedSource = normalizeKey(source)
        let remoteItems: [Item] = try await enumerate(at: source, recursively: true)
        var remoteItemsByRelativePath = [String: Item]()

        for item in remoteItems {
            let normalizedItemPath = normalizeKey(item.path)
            let relativePath = normalizeKey(String(normalizedItemPath.dropFirst(normalizedSource.count)))
            remoteItemsByRelativePath[relativePath] = item
        }

        // Compare and derive actions.
        // Create remote directories locally, shallowest first.

        let remoteDirectories = remoteItems
            .filter(\.isDirectory)
            .sorted { $0.path.components(separatedBy: "/").count < $1.path.components(separatedBy: "/").count }

        for directory in remoteDirectories {
            let normalizedDirectoryPath = normalizeKey(directory.path)
            let relativePath = normalizeKey(String(normalizedDirectoryPath.dropFirst(normalizedSource.count)))
            let localURL = destination.appending(path: relativePath)

            if fileManager.fileExists(atPath: localURL.path(percentEncoded: false)) == false {
                try fileManager.createDirectory(at: localURL, withIntermediateDirectories: true)
            }
        }

        // Download new and changed files.

        let remoteFiles = remoteItems.filter { $0.isDirectory == false }

        for file in remoteFiles {
            let normalizedFilePath = normalizeKey(file.path)
            let relativePath = normalizeKey(String(normalizedFilePath.dropFirst(normalizedSource.count)))
            let localURL = destination.appending(path: relativePath)

            try await downloadFile(file.path, to: localURL, force: force, remoteItem: file)
        }

        // Delete local items not present in the remote state, deepest first so a directory is never removed before its still-pending child entries (`removeItem` on a directory removes recursively, which would invalidate the URLs captured for those children and surface as a confusing failure).

        if force {
            let remoteRelativePaths = Set(remoteItemsByRelativePath.keys)
            let orphanedPaths = localItemsByRelativePath.keys
                .filter { remoteRelativePaths.contains($0) == false }
                .sorted { $0.components(separatedBy: "/").count > $1.components(separatedBy: "/").count }

            for path in orphanedPaths {
                guard let url = localItemsByRelativePath[path] else {
                    continue
                }

                if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                    try fileManager.removeItem(at: url)
                }
            }
        }
    }

    ///
    /// Download implementation specifically for files.
    ///
    private func downloadFile(_ source: String, to destination: URL, force: Bool, remoteItem: Item) async throws {
        logger.debug("Downloading file from \"\(source)\" to \"\(destination.path(percentEncoded: false))\" \(force ? "with" : "without") force...")

        if force == false {
            // Check for the destination file to not exist before starting a potentially long running download.
            try fileManager.assertFileDoesNotExist(at: destination)
        } else if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            // Skip download if the local file is not older than the remote file.
            let attributes = try fileManager.attributesOfItem(atPath: destination.path(percentEncoded: false))

            if let localModification = attributes[.modificationDate] as? Date, localModification >= remoteItem.modification {
                return
            }
        }

        let url = webDAVAddress.appending(path: source)
        let request = try makeWebDAVRequest(for: url, method: .get)
        let (data, urlResponse) = try await session.download(for: request, delegate: nil)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        // Check for the destination file to still not exist after a potentially long running download.
        if force == false {
            try fileManager.assertFileDoesNotExist(at: destination)
        }

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: data, to: destination)

        // Align the local modification date with the remote state for future change detection.
        try fileManager.setAttributes([.modificationDate: remoteItem.modification], ofItemAtPath: destination.path(percentEncoded: false))
    }

    // MARK: - Factory Methods

    ///
    /// Create a new URL request object with some basics configured consistently.
    ///
    private func makeRequest(for url: URL, method: Method) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        return request
    }

    ///
    /// Set up a URL request specifically for WebDAV interaction.
    ///
    private func makeWebDAVRequest(for url: URL, method: Method) throws -> URLRequest {
        guard let user, let password else {
            throw RainmakerError.credentialsRequired
        }

        let encodedCredentials = Data("\(user):\(password)".utf8).base64EncodedString()

        var request = makeRequest(for: url, method: method)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")

        return request
    }

    // MARK: - Initializers

    ///
    /// Create a new server object.
    ///
    /// - Parameters:
    ///     - address: HTTP address of the Nextcloud host.
    ///     - password: In most cases, this is the app password and not the account password.
    ///     - user: The Nextcloud user name used to identify as.
    ///     - userAgent: The user agent to report as in HTTP request headers.
    ///
    public convenience init(address: URL, password: String? = nil, user: String? = nil, userAgent: String = "Rainmaker") {
        let session = URLSession(configuration: .ephemeral)
        self.init(address: address, password: password, user: user, session: session, userAgent: userAgent)
    }

    init(address: URL, password: String? = nil, user: String? = nil, session: any Requesting, userAgent: String) {
        self.address = address
        jsonDecoder = JSONDecoder()
        self.password = password
        self.session = session
        self.user = user
        self.userAgent = userAgent
        webDAVAddress = address.appending(path: "/remote.php/dav/files/\(user ?? "")", directoryHint: .isDirectory)
        webDAVPathPrefix = "/remote.php/dav/files/\(user ?? "")"
    }
}

// MARK: - Serving

extension Server: Serving {
    public func download(_ source: String, to destination: URL, force: Bool) async throws {
        try requireCredentials()
        logger.debug("Downloading \"\(source)\" to \"\(destination.path)\"...")
        let item = try await info(source)

        if item.isDirectory {
            try await downloadDirectory(source, to: destination, force: force)
        } else {
            let destinationFile = destination.appending(component: item.name)
            try await downloadFile(source, to: destinationFile, force: force, remoteItem: item)
        }
    }

    public func enumerate(at path: String, recursively: Bool) async throws -> AsyncThrowingStream<Item, Error> {
        try requireCredentials()

        logger.debug("Enumerating items\(recursively ? " recursively" : "") at path: \(path)")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let items = try await content(at: path)

                    for item in items {
                        continuation.yield(item)

                        guard recursively, item.isDirectory else {
                            continue
                        }

                        logger.debug("Entering subdirectory: \(item.path)")
                        let nestedItems: AsyncThrowingStream<Item, Error> = try await enumerate(at: item.path, recursively: true)

                        for try await nestedItem in nestedItems {
                            continuation.yield(nestedItem)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func enumerate(at path: String, recursively: Bool) async throws -> [Item] {
        var items = [Item]()
        let stream: AsyncThrowingStream<Item, Error> = try await enumerate(at: path, recursively: recursively)

        for try await item in stream {
            items.append(item)
        }

        return items
    }

    public func info(_ path: String) async throws -> Item {
        try requireCredentials()
        logger.debug("Fetching information about \(path)")
        let items = try await content(at: path, depth: 0)

        guard let item = items.first else {
            throw RainmakerError.responseDecodingFailed(reason: "Expected at least one item to be found but there was none.")
        }

        return item
    }

    public func login() async throws -> LoginFlow {
        logger.debug("Fetching login information...")

        let url = address.appending(path: "index.php/login/v2", directoryHint: .notDirectory)
        let request = makeRequest(for: url, method: .post)
        let (data, _) = try await session.data(for: request)
        let dataTransferObject = try jsonDecoder.decode(LoginFlowResponse.self, from: data)
        return LoginFlow(endpoint: dataTransferObject.poll.endpoint, entry: dataTransferObject.login, token: dataTransferObject.poll.token)
    }

    public func poll(_ endpoint: URL, token: String) async throws -> LoginResult {
        logger.debug("Polling \(endpoint.absoluteString)")

        var request = makeRequest(for: endpoint, method: .post)
        request.httpBody = "token=\(token)".data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        let stringRepresentation = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard stringRepresentation != "[]" else {
            throw RainmakerError.responseDecodingFailed(reason: "The server returned no login flow result on polling.")
        }

        let dataTransferObject = try jsonDecoder.decode(LoginResultResponse.self, from: data)
        return LoginResult(name: dataTransferObject.loginName, password: dataTransferObject.appPassword, server: dataTransferObject.server)
    }
}
