// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// Main type to interact with an account on a Nextcloud server.
///
public final class Server {
    static let resourceURL = Bundle.module.resourceURL!

    ///
    /// The range of page sizes the activity endpoint accepts.
    ///
    /// The server silently reduces anything larger to two hundred and answers with an internal error rather than with a validation error for a page size of zero or below, so ``activities(filter:since:limit:sort:previews:objectType:objectId:)`` clamps to this range before sending the request. Clamping rather than passing the value through keeps the requested page size and the honoured one the same.
    ///
    static let activityLimits = 1 ... 200

    nonisolated(unsafe) let fileManager = FileManager.default
    let logger = Logger(category: "Server")
    let jsonDecoder: JSONDecoder
    let session: any Requesting
    let webSocket: any WebSocketConnecting

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

    public let OCSAddress: URL

    ///
    /// The path prefix appended to the base address before the actual remote subject path on every trash bin WebDAV request, including the user's name.
    ///
    /// Looks like `"/remote.php/dav/trashbin/<user>/trash"`.
    ///
    public let trashbinPathPrefix: String

    ///
    /// WebDAV address of the user's trash bin on the server.
    ///
    public let trashbinAddress: URL

    ///
    /// WebDAV address of the user's restore collection, used as the destination when restoring a trashed item.
    ///
    /// Looks like `"/remote.php/dav/trashbin/<user>/restore"`.
    ///
    public let trashbinRestoreAddress: URL

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
        var request = try makeWebDAVRequest(for: path, method: .propfind)
        request.httpBody = try? Data(contentsOf: Self.resourceURL.appendingCompatibility(component: "Bodies").appendingCompatibility(component: "Listing.xml"))
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
    /// List the content of the user's trash bin.
    ///
    private func trashContent() async throws -> [TrashItem] {
        var request = try makeWebDAVRequest(for: trashbinAddress, method: .propfind)
        request.httpBody = try? Data(contentsOf: Self.resourceURL.appendingCompatibility(component: "Bodies").appendingCompatibility(component: "Trash.xml"))
        request.setValue("1", forHTTPHeaderField: "Depth")

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

        return try ResponseParser.trashItems(from: data, trashbinPathPrefix: trashbinPathPrefix)
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
    /// The result of this method decides which remote items ``uploadDirectory(_:to:force:)`` considers orphaned, so an incomplete result must never be reported as a successful enumeration.
    ///
    /// - Throws: ``RainmakerError/enumeration(_:_:)`` when the local directory cannot be enumerated at all or when enumerating one of its items fails.
    ///
    private func enumerateLocalFiles(at destination: URL) throws -> [String: URL] {
        logger.debug("Enumerating local files at \"\(destination.compatibilityPath(percentEncoded: false))\"...")

        var enumerationErrorItem: URL?
        var enumerationError: (any Error)?

        let localEnumerator = fileManager.enumerator(at: destination, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) { url, error in
            enumerationErrorItem = url
            enumerationError = error
            return false
        }

        // A missing enumerator means the local state could not be determined at all, for example because the directory disappeared or became unreadable after the initial existence check.
        // Returning an empty result in that case would be indistinguishable from a genuinely empty directory, which would make `uploadDirectory(_:to:force:)` classify every remote item as an orphan and delete the entire remote subtree.
        guard let localEnumerator else {
            throw RainmakerError.enumeration(destination, "Failed to enumerate the local directory.")
        }

        var result = [String: URL]()
        // Use path components rather than string-prefix arithmetic so that resolving symlinks (e.g. macOS' `/var` → `/private/var`)
        // or other inconsistencies between the supplied destination URL and the URLs yielded by the enumerator do not skew the relative path.
        let destinationComponents = destination.resolvingSymlinksInPath().pathComponents

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

        // The error handler closure is invoked during iteration, so the check must come after the loop.
        if let enumerationErrorItem, let enumerationError {
            throw RainmakerError.enumeration(enumerationErrorItem, enumerationError.localizedDescription)
        }

        return result
    }

    private func downloadDirectory(_ source: String, to destination: URL, force: Bool) async throws {
        logger.debug("Downloading directory from \"\(source)\" to \"\(destination.compatibilityPath(percentEncoded: false))\" \(force ? "with" : "without") force...")

        if fileManager.fileExists(atPath: destination.compatibilityPath(percentEncoded: false)) == false {
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
            let localURL = destination.appendingCompatibility(path: relativePath)

            if fileManager.fileExists(atPath: localURL.compatibilityPath(percentEncoded: false)) == false {
                try fileManager.createDirectory(at: localURL, withIntermediateDirectories: true)
            }
        }

        // Download new and changed files.

        let remoteFiles = remoteItems.filter { $0.isDirectory == false }

        for file in remoteFiles {
            let normalizedFilePath = normalizeKey(file.path)
            let relativePath = normalizeKey(String(normalizedFilePath.dropFirst(normalizedSource.count)))
            let localURL = destination.appendingCompatibility(path: relativePath)

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

                if fileManager.fileExists(atPath: url.compatibilityPath(percentEncoded: false)) {
                    try fileManager.removeItem(at: url)
                }
            }
        }
    }

    ///
    /// Download implementation specifically for files.
    ///
    private func downloadFile(_ source: String, to destination: URL, force: Bool, remoteItem: Item) async throws {
        logger.debug("Downloading file from \"\(source)\" to \"\(destination.compatibilityPath(percentEncoded: false))\" \(force ? "with" : "without") force...")

        if force == false {
            // Check for the destination file to not exist before starting a potentially long running download.
            try fileManager.assertFileDoesNotExist(at: destination)
        } else if fileManager.fileExists(atPath: destination.compatibilityPath(percentEncoded: false)) {
            // Skip download if the local file is not older than the remote file.
            let attributes = try fileManager.attributesOfItem(atPath: destination.compatibilityPath(percentEncoded: false))

            if let localModification = attributes[.modificationDate] as? Date, localModification >= remoteItem.modification {
                return
            }
        }

        let request = try makeWebDAVRequest(for: source, method: .get)
        let (data, urlResponse) = try await session.download(for: request, delegate: nil)

        // The session materializes the payload in a temporary location which would otherwise be left behind on every failure path below.
        // Once the payload has been staged next to its destination this removal silently does nothing.
        defer {
            try? fileManager.removeItem(at: data)
        }

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

        // Stage the payload next to its destination so that putting it in place stays within one volume.
        // See ``URL/downloadStagingLocation()`` for why the staged location looks the way it does.
        let stagingLocation = destination.downloadStagingLocation()

        // Registered before the move so that a move which fails after having written part of the payload does not leak it either.
        // Removal silently does nothing once the staged payload has been consumed or was never created in the first place.
        defer {
            try? fileManager.removeItem(at: stagingLocation)
        }

        try fileManager.moveItem(at: data, to: stagingLocation)

        if fileManager.fileExists(atPath: destination.compatibilityPath(percentEncoded: false)) {
            // Replacing keeps the existing file intact until the new content is completely in place, unlike deleting it first and moving the replacement afterwards.
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagingLocation)
        } else {
            try fileManager.moveItem(at: stagingLocation, to: destination)
        }

        // Align the local modification date with the remote state for future change detection.
        try fileManager.setAttributes([.modificationDate: remoteItem.modification], ofItemAtPath: destination.compatibilityPath(percentEncoded: false))
    }

    ///
    /// Returns whether the item at the given local URL is a directory.
    ///
    /// This is used to classify the entries returned by ``enumerateLocalFiles(at:)`` which mixes files and directories.
    ///
    private func isDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    ///
    /// Upload implementation specifically for files.
    ///
    /// This is the counterpart of ``downloadFile(_:to:force:remoteItem:)``.
    ///
    private func uploadFile(_ source: URL, to remoteFilePath: String, force: Bool) async throws {
        logger.debug("Uploading file from \"\(source.compatibilityPath(percentEncoded: false))\" to \"\(remoteFilePath)\" \(force ? "with" : "without") force...")

        let attributes = try fileManager.attributesOfItem(atPath: source.compatibilityPath(percentEncoded: false))
        let localModification = attributes[.modificationDate] as? Date

        // Determine the current remote state to decide on conflicts and skipping.
        let remoteItem: Item?

        do {
            remoteItem = try await info(remoteFilePath)
        } catch RainmakerError.notFound {
            remoteItem = nil
        }

        if let remoteItem {
            if force == false {
                throw RainmakerError.fileAlreadyExists(webDAVAddress.appendingCompatibility(path: remoteFilePath))
            }

            // Skip upload if the remote file is not older than the local file.
            if let localModification, remoteItem.modification >= localModification {
                return
            }
        }

        var request = try makeWebDAVRequest(for: remoteFilePath, method: .put)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        // Preserve the local modification date on the server for future change detection.
        // See ``Date/wholeSecondsSince1970`` for why a modification date is not always representable and is then omitted.
        if let modificationSeconds = localModification?.wholeSecondsSince1970 {
            request.setValue("\(modificationSeconds)", forHTTPHeaderField: "X-OC-Mtime")
        }

        let (_, urlResponse) = try await session.upload(for: request, fromFile: source, delegate: nil)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // A missing parent collection makes the server respond with a conflict.
        if response.status == .conflict {
            throw RainmakerError.notFound
        }

        guard response.status == .created || response.status == .noContent else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    ///
    /// Upload implementation specifically for directories.
    ///
    /// This is the counterpart of ``downloadDirectory(_:to:force:)``.
    ///
    private func uploadDirectory(_ source: URL, to destination: String, force: Bool) async throws {
        logger.debug("Uploading directory from \"\(source.compatibilityPath(percentEncoded: false))\" to \"\(destination)\" \(force ? "with" : "without") force...")

        let normalizedDestination = normalizeKey(destination)

        // Ensure the remote destination directory exists, tolerating the case where it already does.
        if normalizedDestination.isEmpty == false {
            do {
                try await createDirectory(destination)
            } catch RainmakerError.fileAlreadyExists {
                // The destination directory already exists which is acceptable.
            }
        }

        // Cancel on a non-empty remote destination unless overwriting is forced.
        if force == false {
            let existingRemoteItems: [Item] = try await enumerate(at: destination, recursively: false)

            if existingRemoteItems.isEmpty == false {
                throw RainmakerError.directoryNotEmpty
            }
        }

        // Enumerate the remote state recursively for later orphan detection.
        let remoteItems: [Item] = try await enumerate(at: destination, recursively: true)

        // Enumerate the local state recursively. This dictionary contains both files and directories which are classified individually below.
        let localItemsByRelativePath = try enumerateLocalFiles(at: source)

        // Create local directories on the remote, shallowest first so a parent always precedes its children.
        let localDirectories = localItemsByRelativePath
            .filter { isDirectory(at: $0.value) }
            .sorted { $0.key.components(separatedBy: "/").count < $1.key.components(separatedBy: "/").count }

        for (relativePath, _) in localDirectories {
            let remotePath = normalizedDestination.isEmpty ? "/\(relativePath)" : "/\(normalizedDestination)/\(relativePath)"

            do {
                try await createDirectory(remotePath)
            } catch RainmakerError.fileAlreadyExists {
                // The remote directory already exists which is acceptable.
            }
        }

        // Upload new and changed files.
        let localFiles = localItemsByRelativePath.filter { isDirectory(at: $0.value) == false }

        for (relativePath, localURL) in localFiles {
            let remotePath = normalizedDestination.isEmpty ? "/\(relativePath)" : "/\(normalizedDestination)/\(relativePath)"
            try await uploadFile(localURL, to: remotePath, force: force)
        }

        // Delete remote items not present in the local state, deepest first so a directory is never removed before its still-pending child entries (deleting a directory removes its contents recursively, which would invalidate the paths captured for those children).
        if force {
            let localRelativePaths = Set(localItemsByRelativePath.keys)

            let orphanedItems = remoteItems
                .filter { localRelativePaths.contains(normalizeKey(String(normalizeKey($0.path).dropFirst(normalizedDestination.count)))) == false }
                .sorted { $0.path.components(separatedBy: "/").count > $1.path.components(separatedBy: "/").count }

            for item in orphanedItems {
                do {
                    try await delete(item.path)
                } catch RainmakerError.notFound {
                    // The remote item was already removed together with a parent directory.
                }
            }
        }
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
    /// Set up a URL request specifically for WebDAV interaction with an absolute URL.
    ///
    /// This is the shared implementation behind ``makeWebDAVRequest(for:method:)`` and the trash bin operations, which target a different WebDAV root than the account's files.
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
    ///     - session: A ``Requesting`` object (e.g. a `URLSession`) to use for network requests. Defaults to a new ephemeral `URLSession`.
    ///     - webSocket: A ``WebSocketConnecting`` object (e.g. a `URLSession`) to open the `notify_push` WebSocket with, used by ``events(_:)``. It is a separate parameter from `session` only because a `URLSession` typed as `any Requesting` does not expose its WebSocket features. Defaults to a new ephemeral `URLSession`, matching `session`, since notify_push authenticates over the socket itself and needs no persistent cookie, credential, or cache storage.
    ///     - userAgent: The user agent to report as in HTTP request headers.
    ///
    public init(address: URL, password: String? = nil, user: String? = nil, session: any Requesting = URLSession(configuration: .ephemeral), webSocket: any WebSocketConnecting = URLSession(configuration: .ephemeral), userAgent: String = "Rainmaker") {
        self.address = address
        jsonDecoder = JSONDecoder()

        // Every JSON date the server sends is ISO 8601, so the strategy belongs on the shared decoder rather than on a throwaway one per endpoint. It is set once here and never changed afterwards, which keeps the decoder as safe to share across calls as it already was.
        jsonDecoder.dateDecodingStrategy = .iso8601

        self.password = password
        self.session = session
        self.webSocket = webSocket
        self.user = user
        self.userAgent = userAgent
        OCSAddress = address.appendingCompatibility(path: "/ocs/v2.php/", directoryHint: .isDirectory)
        webDAVAddress = address.appendingCompatibility(path: "/remote.php/dav/files/\(user ?? "")", directoryHint: .isDirectory)
        webDAVPathPrefix = "/remote.php/dav/files/\(user ?? "")"
        trashbinAddress = address.appendingCompatibility(path: "/remote.php/dav/trashbin/\(user ?? "")/trash", directoryHint: .isDirectory)
        trashbinPathPrefix = "/remote.php/dav/trashbin/\(user ?? "")/trash"
        trashbinRestoreAddress = address.appendingCompatibility(path: "/remote.php/dav/trashbin/\(user ?? "")/restore", directoryHint: .isDirectory)
    }
}

// MARK: - Serving

extension Server: Serving {
    public func download(_ source: String, to destination: URL, force: Bool) async throws {
        try requireCredentials()
        logger.debug("Downloading \"\(source)\" to \"\(destination.compatibilityPath(percentEncoded: false))\"...")
        let item = try await info(source)

        if item.isDirectory {
            try await downloadDirectory(source, to: destination, force: force)
        } else {
            let destinationFile = destination.appendingCompatibility(component: item.name)
            try await downloadFile(source, to: destinationFile, force: force, remoteItem: item)
        }
    }

    public func upload(_ source: URL, to destination: String, force: Bool) async throws {
        try requireCredentials()
        logger.debug("Uploading \"\(source.compatibilityPath(percentEncoded: false))\" to \"\(destination)\"...")

        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: source.compatibilityPath(percentEncoded: false), isDirectory: &isDirectory) else {
            throw RainmakerError.notFound
        }

        if isDirectory.boolValue {
            try await uploadDirectory(source, to: destination, force: force)
        } else {
            let folder = normalizeKey(destination)
            let remoteFilePath = folder.isEmpty ? "/\(source.lastPathComponent)" : "/\(folder)/\(source.lastPathComponent)"
            try await uploadFile(source, to: remoteFilePath, force: force)
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

    public func createDirectory(_ path: String) async throws {
        try requireCredentials()
        logger.debug("Creating directory at \(path)")

        let url = webDAVAddress.appendingCompatibility(path: path)
        let request = try makeWebDAVRequest(for: path, method: .mkcol)
        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        if response.status == .methodNotAllowed {
            throw RainmakerError.fileAlreadyExists(url)
        }

        if response.status == .conflict {
            throw RainmakerError.notFound
        }

        guard response.status == .created else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    public func delete(_ path: String) async throws {
        try requireCredentials()
        logger.debug("Deleting \(path)")

        let request = try makeWebDAVRequest(for: path, method: .delete)
        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .noContent else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    public func move(_ source: String, to destination: String, overwrite: Bool) async throws {
        try requireCredentials()
        logger.debug("Moving \(source) to \(destination)")

        // The Destination header must carry the absolute, percent-encoded target URL.
        let destinationURL = webDAVAddress.appendingCompatibility(path: destination)

        var request = try makeWebDAVRequest(for: source, method: .move)
        request.setValue(destinationURL.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue(overwrite ? "T" : "F", forHTTPHeaderField: "Overwrite")

        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The source does not exist.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        // The destination's parent collection does not exist.
        if response.status == .conflict {
            throw RainmakerError.notFound
        }

        // The destination is occupied and overwriting was not requested.
        if response.status == .preconditionFailed {
            throw RainmakerError.destinationExists(destinationURL)
        }

        // A successful move responds 201 Created (relocated) or 204 No Content (overwrote an existing item).
        guard response.status == .created || response.status == .noContent else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    public func trash() async throws -> [TrashItem] {
        try requireCredentials()
        logger.debug("Listing trash bin contents...")
        return try await trashContent()
    }

    public func restore(_ id: String) async throws {
        try requireCredentials()
        logger.debug("Restoring trashed item \(id)")

        // Restoring is a MOVE into the restore collection. The destination name is ignored by the server, which restores the item to its original location.
        let source = trashbinAddress.appendingCompatibility(path: id, directoryHint: .notDirectory)
        let destination = trashbinRestoreAddress.appendingCompatibility(path: id, directoryHint: .notDirectory)

        var request = try makeWebDAVRequest(for: source, method: .move)
        request.setValue(destination.absoluteString, forHTTPHeaderField: "Destination")

        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The trashed item does not exist.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        // The restore collection's parent does not exist, e.g. the trash bin is unavailable.
        if response.status == .conflict {
            throw RainmakerError.notFound
        }

        // A successful restore responds 201 Created or 204 No Content.
        guard response.status == .created || response.status == .noContent else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    public func restore(_ item: TrashItem) async throws {
        try await restore(item.id)
    }

    public func emptyTrash() async throws {
        try requireCredentials()
        logger.debug("Emptying trash bin...")

        let request = try makeWebDAVRequest(for: trashbinAddress, method: .delete)
        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        guard response.status == .noContent else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    public func login() async throws -> LoginFlow {
        logger.debug("Fetching login information...")

        let url = address.appendingCompatibility(path: "index.php/login/v2", directoryHint: .notDirectory)
        let request = makeRequest(for: url, method: .post)
        let (data, _) = try await session.data(for: request)
        let dataTransferObject = try jsonDecoder.decode(LoginFlowResponse.self, from: data)
        return LoginFlow(endpoint: dataTransferObject.poll.endpoint, entry: dataTransferObject.login, token: dataTransferObject.poll.token)
    }

    public func capabilities() async throws -> CapabilitySet {
        logger.debug("Fetching server capabilities...")

        let request = try makeOCSRequest(for: "cloud/capabilities", method: .get)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        // Decode the parts of the OCS envelope with a known, stable shape: the status and the version.
        let envelope = try jsonDecoder.decode(CapabilitiesResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        // The capabilities object itself is open-ended, so keep its raw bytes for on-demand parsing.
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ocs = root["ocs"] as? [String: Any],
            let payload = ocs["data"] as? [String: Any],
            let capabilities = payload["capabilities"]
        else {
            throw RainmakerError.responseDecodingFailed(reason: "Missing capabilities in OCS response.")
        }

        let raw = try JSONSerialization.data(withJSONObject: capabilities)

        return CapabilitySet(version: envelope.ocs.data.version, raw: raw)
    }

    public func navigation() async throws -> [NavigationItem] {
        try requireCredentials()
        logger.debug("Fetching apps navigation...")

        let request = try makeOCSRequest(for: "core/navigation/apps", method: .get)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let envelope = try jsonDecoder.decode(NavigationResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        return envelope.ocs.data
    }

    public func notifications() async throws -> [NotificationItem] {
        try requireCredentials()
        logger.debug("Fetching user notifications...")

        let request = try makeOCSRequest(for: "apps/notifications/api/v2/notifications", method: .get)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint only exists while the notifications app is installed and enabled, so its absence surfaces as a not found error.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let envelope = try jsonDecoder.decode(NotificationsResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        return envelope.ocs.data
    }

    public func activities(filter: String = ActivityFilter.all, since: Int = 0, limit: Int = 50, sort: ActivitySort = .newestFirst, previews: Bool = false, objectType: String? = nil, objectId: String? = nil) async throws -> ActivityPage {
        try requireCredentials()
        logger.debug("Fetching user activities...")

        var effectiveFilter = filter
        var objectQueryItems = [URLQueryItem]()

        // Narrowing the stream down to a single object is a filter of its own on the server, so naming the object implies that filter and the caller does not have to know about it.
        if let objectType, let objectId {
            effectiveFilter = ActivityFilter.object
            objectQueryItems = [URLQueryItem(name: "object_type", value: objectType), URLQueryItem(name: "object_id", value: objectId)]
        }

        // The server answers with an internal error rather than with a validation error when the page size is out of range, so it is kept within the accepted bounds here.
        let effectiveLimit = min(max(limit, Server.activityLimits.lowerBound), Server.activityLimits.upperBound)

        var queryItems = [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(effectiveLimit)),
            URLQueryItem(name: "sort", value: sort.rawValue),
        ]

        if previews {
            queryItems.append(URLQueryItem(name: "previews", value: "true"))
        }

        queryItems.append(contentsOf: objectQueryItems)

        let request = try makeOCSRequest(for: "apps/activity/api/v2/activity/\(effectiveFilter)", method: .get, queryItems: queryItems)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        let firstKnown = response.value(forHTTPHeaderField: "X-Activity-First-Known").flatMap { Int($0) }
        let lastGiven = response.value(forHTTPHeaderField: "X-Activity-Last-Given").flatMap { Int($0) }

        // An empty result carries no body to decode, so it becomes an empty page rather than an error. The server reports the end of the stream as not modified, and its endpoint also declares a no content answer for an account with no activity settings enabled, which activity app 7.0.0 has no reachable path to but which is handled here all the same.
        if response.status == .notModified || response.status == .noContent {
            return ActivityPage(items: [], firstKnown: firstKnown, lastGiven: lastGiven)
        }

        // The endpoint only exists while the activity app is installed and enabled, so its absence surfaces as a not found error. An unknown filter is reported the same way.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let envelope = try jsonDecoder.decode(ActivityResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        return ActivityPage(items: envelope.ocs.data, firstKnown: firstKnown, lastGiven: lastGiven)
    }

    public func activityFilters() async throws -> [ActivityFilter] {
        try requireCredentials()
        logger.debug("Fetching activity filters...")

        let request = try makeOCSRequest(for: "apps/activity/api/v2/activity/filters", method: .get)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint only exists while the activity app is installed and enabled, so its absence surfaces as a not found error.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let envelope = try jsonDecoder.decode(ActivityFiltersResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        return envelope.ocs.data
    }

    public func makeOCSRequest(for path: String, method: Method, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let url = OCSAddress.appendingCompatibility(path: path, directoryHint: .inferFromPath)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // The query is only assigned when there is one so that a request without query parameters produces a bare URL rather than one with a trailing question mark.
        if queryItems.isEmpty == false {
            components?.queryItems = queryItems
        }

        var request = makeRequest(for: components?.url ?? url, method: method)
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")

        if let user, let password {
            let encodedCredentials = Data("\(user):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    public func makeWebDAVRequest(for path: String, method: Method) throws -> URLRequest {
        try makeWebDAVRequest(for: webDAVAddress.appendingCompatibility(path: path, directoryHint: .inferFromPath), method: method)
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

    public func deleteAppPassword() async throws {
        try requireCredentials()
        logger.debug("Deleting app password...")

        let request = try makeOCSRequest(for: "core/apppassword", method: .delete)
        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }
}
