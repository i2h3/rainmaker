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

    ///
    /// The chunk size ``upload(_:to:force:chunkSize:)`` uses when the caller does not choose one, which is 10 MiB.
    ///
    /// This matches the default of the official desktop client. It keeps a single request well below what reverse proxies commonly cap request bodies at, see ``ChunkedUpload/maxSize``, while a file of many gigabytes still fits into the ten thousand chunks a transfer may consist of.
    ///
    public static let defaultChunkSize = 10 * 1024 * 1024

    ///
    /// The smallest chunk size ``upload(_:to:force:chunkSize:)`` sends, which is 5 MiB.
    ///
    /// A server keeping its files in an S3 compatible object storage assembles the chunks as a multipart upload, and S3 rejects every part but the last below this size. Such a server reports that only when the transfer is finalized, after every chunk has already been sent, so a smaller requested chunk size is raised to this one before anything is sent rather than being passed through.
    ///
    public static let minimumChunkSize = 5 * 1024 * 1024

    ///
    /// The number of chunks a single transfer may consist of at most, which the server limits to ten thousand.
    ///
    /// ``effectiveChunkSize(for:requested:)`` raises the chunk size as far as needed for a file to fit into this many chunks.
    ///
    static let maximumChunkCount: Int64 = 10000

    ///
    /// The number of bytes copied at once while a chunk is staged into a temporary file, which is 1 MiB.
    ///
    /// Staging copies through a buffer of this size rather than reading a whole chunk into memory, so the memory a chunked upload needs does not grow with the chunk size.
    ///
    static let stagingBufferSize = 1024 * 1024

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

    ///
    /// Root address of the server's OCS API.
    ///
    /// Looks like `"/ocs/v2.php/"` and is what ``makeOCSRequest(for:method:queryItems:)`` resolves its path against.
    ///
    public let OCSAddress: URL

    ///
    /// Root address of the server apps' own REST APIs, which are reachable outside the OCS root.
    ///
    /// Looks like `"/index.php/apps/"` and is what ``makeAppRequest(for:method:queryItems:)`` resolves its path against.
    ///
    public let appsAddress: URL

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

    ///
    /// WebDAV address of the user's upload collection, below which ``upload(_:to:force:chunkSize:)`` stages the chunks of a large file until the server assembles them.
    ///
    /// Looks like `"/remote.php/dav/uploads/<user>"`.
    ///
    public let uploadsAddress: URL

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
    /// Request an endpoint of the notes app's API and return its raw payload.
    ///
    /// This is what every notes feature shares: the base path, the mapping of an absent app onto a not found error, and the enforcement of ``Notes/minimumAPIVersion``.
    ///
    /// None of those endpoints answers with an OCS envelope, so unlike every other JSON endpoint in this library there is no `meta` status vouching for a payload. A success response carrying something else entirely, for example an HTML login or maintenance page served by a proxy, therefore has to surface as ``RainmakerError/responseDecodingFailed(reason:)`` rather than as an opaque Foundation error, which is why every caller wraps its decoding. The payload is left out of those messages so that note contents cannot leak into logs.
    ///
    /// - Parameters:
    ///     - path: The path relative to the notes app's API root, e.g. `"notes"` or `"settings"`.
    ///     - queryItems: The query parameters to append, in the order they should appear.
    ///
    private func notesAPIPayload(for path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let request = try makeAppRequest(for: "notes/api/v1/\(path)", method: .get, queryItems: queryItems)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint only exists while the notes app is installed and enabled, so its absence surfaces as a not found error. A notes app too old to serve this major version of the API is reported the same way.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        // Every response of the notes API advertises which versions of it the installed app can serve, so the requirement is enforced from the response already in hand rather than by asking for the server's capabilities first.
        let advertisedAPIVersions = (response.value(forHTTPHeaderField: "X-Notes-API-Versions") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }

        guard Notes.supports(apiVersions: advertisedAPIVersions) else {
            throw RainmakerError.unsupportedAPIVersion(app: Notes.key, required: Notes.minimumAPIVersion, advertised: advertisedAPIVersions)
        }

        return data
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
    /// This is the counterpart of ``downloadFile(_:to:force:remoteItem:)``. It decides whether the remote state calls for an upload at all, and then whether the file is small enough for a single request or has to go through ``uploadFileChunked(_:to:size:chunkSize:modification:)``.
    ///
    private func uploadFile(_ source: URL, to remoteFilePath: String, force: Bool, chunkSize: Int) async throws {
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

        // A file larger than a chunk is not sent in one request but staged in chunks the server assembles, which keeps it within the request size and time limits of the server and any reverse proxy in front of it.
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let effectiveChunkSize = Self.effectiveChunkSize(for: size, requested: chunkSize)

        if size > effectiveChunkSize {
            try await uploadFileChunked(source, to: remoteFilePath, size: size, chunkSize: effectiveChunkSize, modification: localModification)
            return
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
    private func uploadDirectory(_ source: URL, to destination: String, force: Bool, chunkSize: Int) async throws {
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
            try await uploadFile(localURL, to: remotePath, force: force, chunkSize: chunkSize)
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

    ///
    /// The chunk size actually used for a file of the given size when the given one was requested.
    ///
    /// The requested size is raised to ``minimumChunkSize`` and beyond that as far as needed for the file to fit into ``maximumChunkCount`` chunks. It is never lowered, so a caller who has read ``ChunkedUpload/maxSize`` and stays below it keeps what they asked for.
    ///
    static func effectiveChunkSize(for size: Int64, requested chunkSize: Int) -> Int64 {
        let smallestFitting = (size + Self.maximumChunkCount - 1) / Self.maximumChunkCount
        return max(Int64(chunkSize), Int64(Self.minimumChunkSize), smallestFitting)
    }

    ///
    /// The name of the folder below ``uploadsAddress`` in which the chunks of the given file are staged.
    ///
    /// It is derived from the remote path, the size and the modification date rather than drawn at random, so that uploading the same file to the same place always uses the same folder, which keeps the requests of a transfer reproducible, while a changed file uses a different one. Two devices uploading the same version of a file at the same time therefore share a folder, which is harmless because they send identical chunks.
    ///
    static func uploadTransferName(for remoteFilePath: String, size: Int64, modification: Date?) -> String {
        String(Data("\(remoteFilePath)\n\(size)\n\(modification?.wholeSecondsSince1970 ?? 0)".utf8).sha256HexString.prefix(32))
    }

    ///
    /// Upload a single large file in chunks which the server assembles into the file at the given remote path.
    ///
    /// This is the chunked counterpart of the single request in ``uploadFile(_:to:force:chunkSize:)``, which decides between the two. The transfer follows the server's chunked upload protocol: a folder named by ``uploadTransferName(for:size:modification:)`` is created below ``uploadsAddress``, every chunk is sent into it under its one-based position, and a final move of the folder's virtual `.file` makes the server assemble the chunks into the destination. A folder left behind by an interrupted attempt is removed before the transfer starts over, so the server never assembles chunks of two attempts, and a failure at any point removes the folder again.
    ///
    /// Every request names the final destination in its `Destination` header, which is what makes a server backed by an object storage stream the chunks straight into their final place, and the total size in `OC-Total-Length`, which a server keeping its files locally checks against the assembled size before it puts the file in place and which lets both reject a file exceeding the quota before the first chunk is stored.
    ///
    /// The file is checked for changes once every chunk has been read, because a file which changed underneath the transfer would be assembled from chunks of two different versions. Such a transfer is abandoned with ``RainmakerError/sourceChanged(_:)`` rather than finalized.
    ///
    private func uploadFileChunked(_ source: URL, to remoteFilePath: String, size: Int64, chunkSize: Int64, modification: Date?) async throws {
        let destination = webDAVAddress.appendingCompatibility(path: remoteFilePath)
        let transfer = uploadsAddress.appendingCompatibility(path: Self.uploadTransferName(for: remoteFilePath, size: size, modification: modification), directoryHint: .notDirectory)
        logger.debug("Uploading \(size) bytes in chunks of \(chunkSize) bytes via \"\(transfer.absoluteString)\"...")

        try await createUploadTransfer(at: transfer, destination: destination)

        do {
            let handle = try FileHandle(forReadingFrom: source)

            defer {
                try? handle.close()
            }

            var offset: Int64 = 0
            var position = 1

            while offset < size {
                let length = min(chunkSize, size - offset)
                let staged = try stageChunk(from: handle, of: source, length: length)

                defer {
                    try? fileManager.removeItem(at: staged)
                }

                try await uploadChunk(at: staged, position: position, transfer: transfer, destination: destination, totalSize: size)
                offset += length
                position += 1
            }

            // The attributes are read again rather than the sent bytes being compared, because a file replaced in place by one of the same size would otherwise go unnoticed.
            let attributes = try fileManager.attributesOfItem(atPath: source.compatibilityPath(percentEncoded: false))

            guard (attributes[.size] as? NSNumber)?.int64Value == size, attributes[.modificationDate] as? Date == modification else {
                throw RainmakerError.sourceChanged(source)
            }

            try await finishUploadTransfer(transfer, destination: destination, totalSize: size, modification: modification)
        } catch {
            // The folder is removed on a best effort basis so that a failed transfer does not occupy the account's quota until the server expires it. A failure of the removal must not mask the error being reported.
            try? await deleteUploadTransfer(transfer)
            throw error
        }
    }

    ///
    /// Copy the next `length` bytes from the given handle into a temporary file and return its location.
    ///
    /// A chunk is staged as a file of its own so that it can be sent the same way a whole file is, streamed from disk by the session rather than held in memory, and the copy goes through a buffer of ``stagingBufferSize`` for the same reason. The caller removes the staged file once it has been sent.
    ///
    /// - Throws: ``RainmakerError/sourceChanged(_:)`` when the file ends before `length` bytes could be read, which means it shrank since its size was determined.
    ///
    private func stageChunk(from handle: FileHandle, of source: URL, length: Int64) throws -> URL {
        let location = fileManager.temporaryDirectory.appendingCompatibility(component: ".rainmaker-\(UUID().uuidString).chunk", directoryHint: .notDirectory)
        try Data().write(to: location)

        do {
            let output = try FileHandle(forWritingTo: location)

            defer {
                try? output.close()
            }

            var remaining = length

            while remaining > 0 {
                let count = Int(min(Int64(Self.stagingBufferSize), remaining))

                guard let buffer = try handle.read(upToCount: count), buffer.isEmpty == false else {
                    throw RainmakerError.sourceChanged(source)
                }

                try output.write(contentsOf: buffer)
                remaining -= Int64(buffer.count)
            }
        } catch {
            try? fileManager.removeItem(at: location)
            throw error
        }

        return location
    }

    ///
    /// Create the folder a chunked upload is staged in, replacing one left behind by an interrupted attempt.
    ///
    /// The destination is named already here because a server backed by an object storage decides at this point where the chunks are streamed to. A server keeping its files locally ignores it.
    ///
    private func createUploadTransfer(at transfer: URL, destination: URL, replacingExisting: Bool = true) async throws {
        var request = try makeWebDAVRequest(for: transfer, method: .mkcol)
        request.setValue(destination.absoluteString, forHTTPHeaderField: "Destination")

        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // An existing folder was left behind by an interrupted attempt. It is removed and created anew rather than reused, so that the server never assembles chunks of two attempts, and only once so that a server answering this way for another reason cannot keep this going forever.
        if response.status == .methodNotAllowed, replacingExisting {
            try await deleteUploadTransfer(transfer)
            try await createUploadTransfer(at: transfer, destination: destination, replacingExisting: false)
            return
        }

        guard response.status == .created else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    ///
    /// Send one staged chunk into the transfer folder under its one-based position, which is the order the server assembles the chunks in.
    ///
    private func uploadChunk(at staged: URL, position: Int, transfer: URL, destination: URL, totalSize: Int64) async throws {
        var request = try makeWebDAVRequest(for: transfer.appendingCompatibility(path: String(position), directoryHint: .notDirectory), method: .put)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(destination.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue(String(totalSize), forHTTPHeaderField: "OC-Total-Length")

        let (_, urlResponse) = try await session.upload(for: request, fromFile: staged, delegate: nil)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // A chunk answers 201 Created, or 204 No Content when it replaces one of an earlier attempt.
        guard response.status == .created || response.status == .noContent else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    ///
    /// Make the server assemble the chunks of a transfer into the destination file, which also removes the transfer folder.
    ///
    private func finishUploadTransfer(_ transfer: URL, destination: URL, totalSize: Int64, modification: Date?) async throws {
        var request = try makeWebDAVRequest(for: transfer.appendingCompatibility(path: ".file", directoryHint: .notDirectory), method: .move)
        request.setValue(destination.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue("T", forHTTPHeaderField: "Overwrite")
        request.setValue(String(totalSize), forHTTPHeaderField: "OC-Total-Length")

        // Preserve the local modification date on the server for future change detection, exactly as the single request of a small file does.
        if let modificationSeconds = modification?.wholeSecondsSince1970 {
            request.setValue("\(modificationSeconds)", forHTTPHeaderField: "X-OC-Mtime")
        }

        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // A missing parent collection makes the server respond with a conflict, as it does for a single request.
        if response.status == .conflict {
            throw RainmakerError.notFound
        }

        // The destination is occupied although overwriting was requested, which a locked file can cause.
        if response.status == .preconditionFailed {
            throw RainmakerError.destinationExists(destination)
        }

        // Assembling answers 201 Created for a new file or 204 No Content for an overwritten one.
        guard response.status == .created || response.status == .noContent else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    ///
    /// Remove the folder of a transfer together with every chunk in it.
    ///
    /// A folder which is already gone is not an error: the server removes it by itself once the chunks have been assembled and expires a stale one after a day.
    ///
    private func deleteUploadTransfer(_ transfer: URL) async throws {
        let request = try makeWebDAVRequest(for: transfer, method: .delete)
        let (_, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        guard response.status == .noContent || response.status == .notFound else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
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

        // Every request authenticates itself, so cookies have no part to play and are refused in both directions. Accepting them is actively harmful: a request to an app's own API makes the server open a session and send its cookies back, and a later WebDAV request carrying them is authenticated through that session instead of through its own credentials, which then fails the server's cross-site request check. The symptom is a WebDAV call answering 401 or 412 for no reason other than an unrelated call having preceded it. OCS requests avoid this by announcing themselves as such, which no other endpoint has an equivalent for.
        request.httpShouldHandleCookies = false

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
        appsAddress = address.appendingCompatibility(path: "/index.php/apps/", directoryHint: .isDirectory)
        webDAVAddress = address.appendingCompatibility(path: "/remote.php/dav/files/\(user ?? "")", directoryHint: .isDirectory)
        webDAVPathPrefix = "/remote.php/dav/files/\(user ?? "")"
        trashbinAddress = address.appendingCompatibility(path: "/remote.php/dav/trashbin/\(user ?? "")/trash", directoryHint: .isDirectory)
        trashbinPathPrefix = "/remote.php/dav/trashbin/\(user ?? "")/trash"
        trashbinRestoreAddress = address.appendingCompatibility(path: "/remote.php/dav/trashbin/\(user ?? "")/restore", directoryHint: .isDirectory)
        uploadsAddress = address.appendingCompatibility(path: "/remote.php/dav/uploads/\(user ?? "")", directoryHint: .isDirectory)
    }
}

// MARK: - Serving

extension Server: Serving {
    ///
    /// Download a file or a directory including its contents from the server to the local file system.
    ///
    /// This can be used as a one-way synchronization mechanism to replicate remote content locally.
    /// In combination with the enumeration methods, a metadata-only synchronization is also possible.
    ///
    /// This method behaves differently given its arguments:
    ///
    /// | Type | Source | Destination | Force | Behavior |
    /// | - | - | - | - | - |
    /// | File | Exists | Empty | `false` | Download to destination directory |
    /// | File | Exists | Contains file with same name | `false` | Cancel with conflict error |
    /// | File | Exists | Contains file with same name | `true` | Skip if the local file is not older than the remote file, overwrite otherwise |
    /// | File | Changed | Contains file with same name | `true` | Overwrite local file |
    /// | Directory | Exists | Empty | `false` | Download content of source directory to destination directory |
    /// | Directory | Exists | Not empty | `false` | Cancel with conflict error |
    /// | Directory | Exists | Not empty | `true` | Delete local files which are not present in the remote state, replace local files with the state of their remote counterparts, download locally missing files which exist in the remote state  |
    ///
    /// - Parameters:
    ///     - source: The file or root directory to download.
    ///       This can be either a file or a directory.
    ///     - destination: The directory in the local file system to download to.
    ///       For directory downloads, this directory is created automatically when it does not yet exist.
    ///       The content of the source is placed directly into that directory.
    ///     - force: Whether the local state should be overwritten with the remote state or not. This is `false` by default.
    ///
    /// - Throws:
    ///     - If a file is downloaded and an equally named file already exists in the destination directory.
    ///     - If a directory is downloaded and the destination directory is not empty.
    ///
    public func download(_ source: String, to destination: URL, force: Bool = false) async throws {
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

    ///
    /// Upload a file or a directory including its contents from the local file system to the server.
    ///
    /// This is the counterpart of ``download(_:to:force:)`` and can be used as a one-way synchronization mechanism to replicate local content remotely.
    ///
    /// This method behaves differently given its arguments:
    ///
    /// | Type | Source | Destination | Force | Behavior |
    /// | - | - | - | - | - |
    /// | File | Exists | No equally named remote item | `false` | Upload into the destination directory |
    /// | File | Exists | Contains item with same name | `false` | Cancel with conflict error |
    /// | File | Exists | Contains item with same name | `true` | Skip if the remote file is not older than the local file, overwrite otherwise |
    /// | File | Changed | Contains item with same name | `true` | Overwrite remote file |
    /// | File | Larger than `chunkSize` | any | any | As above, but sent in chunks the server assembles |
    /// | Directory | Exists | Empty or absent | `false` | Upload content of source directory into destination directory |
    /// | Directory | Exists | Not empty | `false` | Cancel with conflict error |
    /// | Directory | Exists | Not empty | `true` | Delete remote items which are not present in the local state, replace remote files with the state of their local counterparts, upload remotely missing files which exist in the local state |
    ///
    /// The local modification date of an uploaded file is preserved on the server via the `X-OC-Mtime` header so that future synchronization runs can detect unchanged files.
    /// The header is omitted for a modification date at or before the Unix epoch and for one which cannot be expressed as a whole number of seconds, in which case the server records the upload time instead.
    ///
    /// A file larger than `chunkSize` is not sent in a single request but as a sequence of chunks the server assembles once the last one has arrived, which keeps uploads of large files within the request size and time limits of the server and any reverse proxy in front of it.
    /// The chunks are staged in a folder below ``uploadsAddress`` and sent one after another; a failure at any point removes that folder again, and the server discards a stale one by itself after a day.
    /// The chunk size is raised to ``minimumChunkSize`` when a smaller one is requested, because a server backed by an object storage rejects smaller chunks, and beyond that as far as needed for the file to fit into the ten thousand chunks a transfer may consist of. It should not exceed the ``ChunkedUpload/maxSize`` the server advertises, which is not enforced here because the server does not enforce it either.
    /// A file which changes while it is being uploaded is not assembled on the server; the upload fails with ``RainmakerError/sourceChanged(_:)`` instead.
    ///
    /// - Parameters:
    ///     - source: The file or root directory in the local file system to upload.
    ///       This can be either a file or a directory.
    ///     - destination: The remote directory to upload into.
    ///       For directory uploads, this directory is created automatically when it does not yet exist.
    ///       The content of the source is placed directly into that directory.
    ///     - force: Whether the remote state should be overwritten with the local state or not. This is `false` by default.
    ///     - chunkSize: The size in bytes of the chunks a file larger than this is uploaded in. Defaults to ``defaultChunkSize``.
    ///
    /// - Throws:
    ///     - ``RainmakerError/notFound`` when the local source does not exist.
    ///     - ``RainmakerError/fileAlreadyExists(_:)`` when a file is uploaded and an equally named remote item already exists while `force` is `false`.
    ///     - ``RainmakerError/directoryNotEmpty`` when a directory is uploaded into a non-empty remote directory while `force` is `false`.
    ///     - ``RainmakerError/sourceChanged(_:)`` when a file changed while it was being uploaded in chunks.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response, such as `507` when the account's quota is exhausted.
    ///
    public func upload(_ source: URL, to destination: String, force: Bool = false, chunkSize: Int = Server.defaultChunkSize) async throws {
        try requireCredentials()
        logger.debug("Uploading \"\(source.compatibilityPath(percentEncoded: false))\" to \"\(destination)\"...")

        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: source.compatibilityPath(percentEncoded: false), isDirectory: &isDirectory) else {
            throw RainmakerError.notFound
        }

        if isDirectory.boolValue {
            try await uploadDirectory(source, to: destination, force: force, chunkSize: chunkSize)
        } else {
            let folder = normalizeKey(destination)
            let remoteFilePath = folder.isEmpty ? "/\(source.lastPathComponent)" : "/\(folder)/\(source.lastPathComponent)"
            try await uploadFile(source, to: remoteFilePath, force: force, chunkSize: chunkSize)
        }
    }

    ///
    /// Returns items in the given path.
    ///
    /// The use of an asynchronous stream makes it suitable for paginated and continuous processing without waiting for all results to come in first.
    /// This can also avoid peaks in memory usage.
    ///
    /// - Parameters:
    ///     - path: The root directory to enter.
    ///     - recursively: Whether subdirectories should be traversed, too.
    ///
    /// - Throws: Any error that might occur during the listing of a remote directory.
    ///
    /// ## Usage
    ///
    /// You can either process items asynchronously as they arrive:
    ///
    /// ```swift
    /// let stream: AsyncThrowingStream<Item, Error> = try await server.enumerate(at: "/", recursively: false)
    ///
    /// for try await item in stream {
    ///     print(item)
    /// }
    /// ```
    ///
    /// Or you can collect all items in an array before processing them at once:
    ///
    /// ```swift
    /// let items: [Item] = try await server.enumerate(at: "/", recursively: false)
    ///
    /// for item in items {
    ///     print(item)
    /// }
    /// ```
    ///
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

    ///
    /// A convenience wrapper that aggregates all items first before returning.
    ///
    /// > Warning: It is recommended to use the equally named streaming alternative which returns an `AsyncThrowingStream` whenever possible.
    /// Using this method may result in high memory peaks in case of large hierarchies in recursive enumeration.
    ///
    /// - Parameters:
    ///     - path: The root directory to enter.
    ///     - recursively: Whether subdirectories should be traversed, too.
    ///
    /// - Returns: All items found at the given path (and, optionally, in its subdirectories) collected in an array.
    ///
    /// - Throws: Any error that might occur during the listing of a remote directory.
    ///
    public func enumerate(at path: String, recursively: Bool) async throws -> [Item] {
        var items = [Item]()
        let stream: AsyncThrowingStream<Item, Error> = try await enumerate(at: path, recursively: recursively)

        for try await item in stream {
            items.append(item)
        }

        return items
    }

    ///
    /// Retrieve the information about a single specific item itself.
    ///
    /// This does not retrieve actual content but only metadata.
    ///
    /// - Parameters:
    ///     - path: The item to retrieve the metadata of.
    ///
    /// - Returns: The metadata for the specific item identified by the given path.
    ///
    /// - Throws: Any error that might occur during retrieval of the item properties.
    ///
    public func info(_ path: String) async throws -> Item {
        try requireCredentials()
        logger.debug("Fetching information about \(path)")
        let items = try await content(at: path, depth: 0)

        guard let item = items.first else {
            throw RainmakerError.responseDecodingFailed(reason: "Expected at least one item to be found but there was none.")
        }

        return item
    }

    ///
    /// Create a new directory at the given remote path.
    ///
    /// Only a single directory level is created, so the parent directory must already exist.
    /// This maps to a WebDAV `MKCOL` request against the target path.
    ///
    /// - Parameters:
    ///     - path: The remote path of the directory to create.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/fileAlreadyExists(_:)`` when a file or directory already exists at the given path.
    ///     - ``RainmakerError/notFound`` when the parent directory does not exist.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other unexpected server response.
    ///
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

    ///
    /// Delete a remote item.
    ///
    /// Deleting a directory removes it together with all of its contents recursively.
    /// On Nextcloud, deleted items are moved to the server-side trash bin and can be restored there.
    ///
    /// - Parameters:
    ///     - path: The remote path of the file or directory to delete.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when no item exists at the given path.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///
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

    ///
    /// Relocate (move and/or rename) a remote file or directory to another remote path on the server.
    ///
    /// Both `source` and `destination` are remote paths on the same account.
    /// This performs a server-side WebDAV `MOVE`; nothing is downloaded locally.
    /// It works identically for files and for directories (collections), relocating the whole subtree in a single request.
    /// Renaming is just a move whose destination has a different last path component.
    ///
    /// This method behaves differently given its arguments:
    ///
    /// | Source | Destination | Overwrite | Behavior |
    /// | - | - | - | - |
    /// | Exists | Free | any | Relocate the item to the destination path |
    /// | Exists | Occupied | `true` | Replace the existing destination with the source |
    /// | Exists | Occupied | `false` | Cancel with conflict error |
    /// | Missing | any | any | Cancel with not found error |
    ///
    /// - Parameters:
    ///     - source: The remote path of the file or directory to relocate.
    ///     - destination: The remote target path. A differing last path component renames the item.
    ///     - overwrite: Whether an item already present at the destination may be replaced.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the source or the destination's parent directory does not exist.
    ///     - ``RainmakerError/destinationExists(_:)`` when the destination is occupied and `overwrite` is `false`.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///
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

    ///
    /// List the items currently in the user's trash bin.
    ///
    /// On Nextcloud, deleting an item moves it to the trash bin from where it can be restored or permanently removed.
    /// Whether the trash bin is available can be checked in advance via the ``Trashing`` capability, e.g. `try await capabilities().get(Trashing.self)?.undelete`.
    ///
    /// - Returns: The trashed items in the order returned by the server.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the trash bin is unavailable.
    ///     - Any other error that might occur during retrieval.
    ///
    public func trash() async throws -> [TrashItem] {
        try requireCredentials()
        logger.debug("Listing trash bin contents...")
        return try await trashContent()
    }

    ///
    /// Restore a trashed item back to its original location.
    ///
    /// The server always restores the item to its original location (``TrashItem/originalLocation``) regardless of the identifier passed.
    ///
    /// - Parameters:
    ///     - id: The identifier of the trashed item to restore, as exposed by ``TrashItem/id``.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when no such trashed item exists or the trash bin is unavailable.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///
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

    ///
    /// Restore a trashed item back to its original location.
    ///
    /// This is a convenience wrapper around ``restore(_:)-(String)`` using the item's ``TrashItem/id``.
    ///
    /// - Parameters:
    ///     - item: The trashed item to restore.
    ///
    public func restore(_ item: TrashItem) async throws {
        try await restore(item.id)
    }

    ///
    /// Permanently empty the entire trash bin.
    ///
    /// This removes every trashed item and cannot be undone.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any non-success response.
    ///
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

    ///
    /// Look up the login flow information.
    ///
    /// - Returns: A set of properties to kick off the authentication which yields an app password.
    ///
    public func login() async throws -> LoginFlow {
        logger.debug("Fetching login information...")

        let url = address.appendingCompatibility(path: "index.php/login/v2", directoryHint: .notDirectory)
        let request = makeRequest(for: url, method: .post)
        let (data, _) = try await session.data(for: request)
        let dataTransferObject = try jsonDecoder.decode(LoginFlowResponse.self, from: data)
        return LoginFlow(endpoint: dataTransferObject.poll.endpoint, entry: dataTransferObject.login, token: dataTransferObject.poll.token)
    }

    ///
    /// Fetch the capabilities advertised by the server.
    ///
    /// Works with or without credentials: when this ``Server`` was created without a user name and password the capabilities are fetched anonymously, which returns the subset of capabilities the server exposes to unauthenticated clients.
    /// When credentials are present the full, account-scoped set is returned.
    ///
    /// - Returns: A ``CapabilitySet`` exposing the server ``Version`` and the advertised capabilities, queryable via ``CapabilitySet/get(_:)``.
    ///
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

    ///
    /// Fetch the apps navigation entries the server advertises for the authenticated user.
    ///
    /// These are the server apps (e.g. Files, Photos, Activity) which a client can surface in its own navigation.
    /// Credentials are required: the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The navigation items in the order returned by the server.
    ///
    /// - Throws: ``RainmakerError/credentialsRequired`` when no credentials are set, or any error that might occur during retrieval.
    ///
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

    ///
    /// List the notifications currently queued for the authenticated user.
    ///
    /// These are provided by the server's bundled notifications app, which is not necessarily installed or enabled. Whether it is available can be checked in advance via the ``Notifications`` capability, e.g. `try await capabilities().contains(Notifications.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/notFound``.
    ///
    /// Downstream projects can derive whether there are any notifications and how many from the returned array via `isEmpty` and `count`.
    ///
    /// Credentials are required: notifications are user-scoped and the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The queued notifications in the order returned by the server, newest first.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notifications app is not available on the server.
    ///     - Any other error that might occur during retrieval.
    ///
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

    ///
    /// List the Nextcloud Talk conversations the authenticated user takes part in.
    ///
    /// These are provided by the server's Talk app which, like the notes app, is not part of a Nextcloud installation and has to be installed separately. Whether it is available can be checked in advance via the ``Talk`` capability, e.g. `try await capabilities().contains(Talk.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/notFound``.
    ///
    /// Every conversation the user takes part in is returned, including the ones the server maintains on its own: the Talk app's own release notes as a ``ConversationType/changelog`` conversation and the account's ``ConversationType/noteToSelf``. Downstream projects can derive whether there are any conversations and how many from the returned array via `isEmpty` and `count`.
    ///
    /// The image of a conversation is retrieved separately through ``conversationAvatar(_:darkTheme:)``.
    ///
    /// Credentials are required: conversations are user-scoped and the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The conversations in the order returned by the server, which the server does not sort deliberately. A client presenting a conversation list is expected to sort it itself, e.g. by ``Conversation/lastActivity`` descending.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the Talk app is not available on the server.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///     - Any other error that might occur during retrieval.
    ///
    public func conversations() async throws -> [Conversation] {
        try requireCredentials()
        logger.debug("Fetching Talk conversations...")

        let request = try makeOCSRequest(for: "apps/spreed/api/v4/room", method: .get)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint only exists while the Talk app is installed and enabled, so its absence surfaces as a not found error.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let envelope = try jsonDecoder.decode(ConversationsResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        return envelope.ocs.data
    }

    ///
    /// Retrieve the image of a single Nextcloud Talk conversation.
    ///
    /// The server resolves which image a conversation has, so this returns whatever it decided on and a client renders it as it comes: a picture a moderator uploaded, an emoji picked in the web interface, the other person's avatar in a ``ConversationType/oneToOne`` conversation, or an icon generated from the kind of conversation it is. The generated icons and the emoji avatars are SVG documents rather than bitmaps, which makes ``ConversationAvatar/contentType`` the field to look at before turning the bytes into an image.
    ///
    /// Each call bypasses the local HTTP cache, because the server permits caching these responses for a day even when the image changes sooner.
    /// Cache the returned image between displays and refresh it when ``Conversation/avatarVersion`` changes or a bounded cache lifetime expires, for example after one day.
    /// An unchanged version is not sufficient to keep an image indefinitely, and for a ``ConversationType/oneToOne`` conversation it says nothing whatsoever: the server derives that marker from the path of a generic icon, so it is identical for every such conversation and never moves when the other person changes their profile picture.
    /// Cache entries must therefore distinguish the server, account, conversation token and appearance rather than the version alone.
    ///
    /// Note that this is served by version 1 of the Talk API while ``conversations()`` is served by version 4. The two are versioned independently.
    ///
    /// Credentials are required, and the same availability considerations as for ``conversations()`` apply.
    ///
    /// - Parameters:
    ///     - token: The ``Conversation/token`` of the conversation to retrieve the image of.
    ///     - darkTheme: Whether to retrieve the variant meant for a dark appearance. Defaults to `false`.
    ///
    /// - Returns: The image bytes together with their MIME type.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when no such conversation exists, it is not accessible to the authenticated user, or the Talk app is not available on the server. The server answers `404` in all of those cases, so they are deliberately not told apart.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when the server does not state the type of the image it sent.
    ///     - Any other error that might occur during retrieval.
    ///
    public func conversationAvatar(_ token: String, darkTheme: Bool = false) async throws -> ConversationAvatar {
        try requireCredentials()
        logger.debug("Fetching the avatar of Talk conversation \(token)...")

        // The dark variant has a sub-route of its own, which the query parameter the endpoint also accepts is deliberately not used for: a path tells the two responses apart wherever requests are keyed by their URL, a query does not.
        let path = darkTheme ? "apps/spreed/api/v1/room/\(token)/avatar/dark" : "apps/spreed/api/v1/room/\(token)/avatar"
        var request = try makeOCSRequest(for: path, method: .get)

        // Talk caches these responses for a day. The caller decides when to refresh an image, so do not reuse an older response from URLSession's cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // The response is an image rather than an OCS payload, so the JSON every other request announces would be a lie. The server answers its error envelope as XML in return, which is why nothing below parses a body.
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint answers the same way for a conversation which does not exist, one this account cannot reach, and a server without the Talk app, so all of those surface as a not found error.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        // Without a stated type the bytes cannot be turned into an image, and guessing between a bitmap and the SVG documents this endpoint commonly serves would be worse than reporting the gap.
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else {
            throw RainmakerError.responseDecodingFailed(reason: "The server did not state the type of the conversation avatar it sent.")
        }

        return ConversationAvatar(data: data, contentType: contentType)
    }

    ///
    /// Retrieve the avatar of a single Nextcloud user.
    ///
    /// The server always answers with an image for a user it knows, drawing one from their initials when they uploaded none, so an empty result is not how an absent picture is reported — ``UserAvatar/isCustom`` is. A client with a monogram of its own must consult it, or it will show the server's placeholder in place of its own.
    ///
    /// Only two sizes exist, which is what ``AvatarSize`` models: the endpoint rounds any other value to one of them and logs the request as deprecated.
    ///
    /// Each call bypasses the local HTTP cache, because the server permits caching these responses for a day even when the picture changes sooner. Cache the returned image between displays and refresh it on a bounded lifetime, keying entries by server, user, size and appearance. The endpoint publishes no version marker for an avatar, so there is nothing cheaper to compare against.
    ///
    /// This is a front page route rather than an OCS or app one, and the server marks it as public. Credentials are required here regardless: an instance may be configured to refuse anonymous requests outright, and asking as the signed-in account is what makes the call behave the same on every instance rather than only on the permissive ones.
    ///
    /// - Parameters:
    ///     - userId: The identifier of the user to retrieve the avatar of, which is their login name rather than their display name.
    ///     - size: Which of the two served sizes to ask for. Defaults to ``AvatarSize/small``.
    ///     - darkTheme: Whether to retrieve the variant meant for a dark appearance. Defaults to `false`.
    ///
    /// - Returns: The image bytes together with their MIME type and whether the user chose the picture themselves.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when no such user exists or the server refused to resolve one. The server answers `404` for both, so they are deliberately not told apart.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when the server does not state the type of the image it sent.
    ///     - Any other error that might occur during retrieval.
    ///
    public func userAvatar(_ userId: String, size: AvatarSize = .small, darkTheme: Bool = false) async throws -> UserAvatar {
        try requireCredentials()
        logger.debug("Fetching the avatar of user \(userId)...")

        // The dark variant has a sub-route of its own, exactly as the Talk conversation avatar does, and is preferred for the same reason: a path tells the two responses apart wherever requests are keyed by their URL.
        var path = "avatar/\(userId)/\(size.rawValue)"

        if darkTheme {
            path += "/dark"
        }

        var request = makeRequest(for: address.appendingCompatibility(path: path, directoryHint: .notDirectory), method: .get)

        // The server caches these responses for a day. The caller decides when to refresh an image, so do not reuse an older response from URLSession's cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // The response is an image rather than a JSON payload, so the type every other request announces would be a lie.
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        // This route is not served through OCS, so credentials are attached here rather than by a request builder which does it on the caller's behalf.
        if let user, let password {
            let encodedCredentials = Data("\(user):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
        }

        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint answers the same way for a user which does not exist and one the server declined to resolve, so both surface as a not found error.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        // Without a stated type the bytes cannot be turned into an image, and guessing would be worse than reporting the gap.
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else {
            throw RainmakerError.responseDecodingFailed(reason: "The server did not state the type of the user avatar it sent.")
        }

        // An absent marker is read as a generated avatar, which is the safe direction: a client drawing its own monogram then draws it, rather than presenting the server's placeholder as somebody's photograph.
        let isCustom = response.value(forHTTPHeaderField: "X-NC-IsCustomAvatar") == "1"

        return UserAvatar(data: data, contentType: contentType, isCustom: isCustom)
    }

    ///
    /// List the collectives the authenticated user is a member of.
    ///
    /// Collectives are the shared, Markdown-based wikis of the [Collectives](https://apps.nextcloud.com/apps/collectives) app which, like the notes app, is not part of a Nextcloud installation and has to be installed separately.
    ///
    /// Unlike every other app this library covers, the Collectives app advertises no capability at all, so its availability cannot be checked through ``capabilities()`` the way ``notes()`` can be checked with the ``Notes`` capability or ``activities(filter:since:limit:sort:previews:objectType:objectId:)`` with the ``Activity`` one. When the app is absent the underlying OCS route does not exist and this call throws ``RainmakerError/notFound``. A client which wants to know in advance can call ``navigation()`` and look for the entry whose ``NavigationItem/id`` is `"collectives"`, which the server advertises exactly while the app is enabled for the user.
    ///
    /// Credentials are required: collectives are user-scoped and the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The collectives in the order returned by the server. Trashed collectives are not included, as the server lists those through a separate endpoint which is out of scope.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the collectives app is not available on the server.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response, such as `403` when the app is installed but not permitted for this user.
    ///     - Any other error that might occur during retrieval.
    ///
    public func collectives() async throws -> [Collective] {
        try requireCredentials()
        logger.debug("Fetching collectives...")

        let request = try makeOCSRequest(for: "apps/collectives/api/v1.0/collectives", method: .get)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint only exists while the collectives app is installed and enabled, so its absence surfaces as a not found error.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let envelope = try jsonDecoder.decode(CollectivesResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        return envelope.ocs.data.collectives
    }

    ///
    /// List the metadata of the pages within a single collective.
    ///
    /// The server returns the whole page hierarchy of the collective at once, flat and fully recursive, so this is a single request no matter how deeply the pages are nested. The hierarchy is passed on unchanged and in the server's order rather than assembled into a tree; it is reconstructed from ``CollectivePage/parentId``, and the page at the root is the one whose ``CollectivePage/isLandingPage`` is `true`.
    ///
    /// This returns page metadata only. The Markdown content of a page lives in a file in the collective's folder, named by ``CollectivePage/fileName`` and ``CollectivePage/filePath``, and retrieving it is out of scope.
    ///
    /// Credentials are required, and the same availability considerations as for ``collectives()`` apply.
    ///
    /// - Parameters:
    ///     - collectiveId: The identifier of the collective to list the pages of, as exposed by ``Collective/id``.
    ///
    /// - Returns: The pages in the order returned by the server, flat and including the page at the root of the collective. Trashed pages are not included.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when no such collective exists, it is not accessible to the authenticated user, or the collectives app is not available on the server. The server answers `404` in all of those cases, so they are deliberately not told apart.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any other non-success response.
    ///     - Any other error that might occur during retrieval.
    ///
    public func pages(inCollective collectiveId: Int) async throws -> [CollectivePage] {
        try requireCredentials()
        logger.debug("Fetching pages of collective \(collectiveId)...")

        let request = try makeOCSRequest(for: "apps/collectives/api/v1.0/collectives/\(collectiveId)/pages", method: .get)
        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        // The endpoint only exists while the collectives app is installed and enabled, and the server answers the same way for a collective which does not exist or which this account cannot reach, so all of those surface as a not found error.
        if response.status == .notFound {
            throw RainmakerError.notFound
        }

        guard response.status == .ok else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        let envelope = try jsonDecoder.decode(PagesResponse.self, from: data)

        guard envelope.ocs.meta.status == "ok" else {
            throw RainmakerError.responseDecodingFailed(reason: "OCS request failed (\(envelope.ocs.meta.statuscode)): \(envelope.ocs.meta.message ?? "No message.")")
        }

        return envelope.ocs.data.pages
    }

    ///
    /// List all notes of the authenticated user.
    ///
    /// Notes are provided by the server's notes app which, unlike most of what this library covers, is not part of a Nextcloud installation and has to be installed separately. Whether it is available can be checked in advance via the ``Notes`` capability, e.g. `try await capabilities().contains(Notes.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/notFound``.
    ///
    /// The very same not found error is what a server answers whose `index.php` routing is disabled or whose reverse proxy swallows the route, so those causes cannot be told apart from the response alone.
    ///
    /// An app which is installed but older than ``Notes/minimumAPIVersion`` is reported separately, as ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``. That requirement is checked on every response, because the notes API advertises the versions it serves in a header of its own, and it can be checked in advance through ``Notes/isSupported``.
    ///
    /// The whole collection is retrieved in a single request, because the endpoint returns everything at once unless a chunk size is requested, which this deliberately does not do. Use ``notes(changedSince:)`` to retrieve only what changed since an earlier call.
    ///
    /// > Warning: Every note including its full content is fetched and held in memory at once, so what this costs grows with the size of the account's notes.
    ///
    /// A note the server could not read is listed like any other and does not fail the call. It carries ``Note/hasError`` and its ``Note/content`` is a message about the failure rather than the note's text, so anything which stores what it retrieves has to check that first.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The notes in the order returned by the server.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    public func notes() async throws -> [Note] {
        try requireCredentials()
        logger.debug("Fetching notes...")

        let data = try await notesAPIPayload(for: "notes")

        do {
            return try jsonDecoder.decode([Note].self, from: data)
        } catch {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to decode the notes: \(error)")
        }
    }

    ///
    /// List the notes of the authenticated user which changed since a given moment, together with the identifiers of those which did not.
    ///
    /// This is the incremental counterpart of ``notes()`` for a client keeping its own copy of the notes: the server returns every note it recorded a change for at or after `changedSince` in full, and reduces every note it did not to its identifier alone. Both together are the complete set of notes the account has, which is what makes deletions detectable. See ``NoteChanges`` for how the two halves are meant to be applied.
    ///
    /// The moment is sent to the server as its `pruneBefore` parameter, converted to whole seconds since the Unix epoch. A moment at or before the epoch prunes nothing and therefore behaves like ``notes()``.
    ///
    /// > Warning: The server compares this moment against its own record of when it last noticed each note change, which is not the same as that note's ``Note/modification`` date. A note may be from 2020, but when the server only found it today it is not pruned from the response. Never pass a note's ``Note/modification`` back in as this moment; pass one measured on the same clock the server runs on instead, such as when the previous retrieval was made. The API defines the exact value to reuse as the `Last-Modified` header of the previous response, which is the server's own request time and which this library does not surface.
    ///
    /// Everything else, including how an unavailable app surfaces and how a note the server could not read is reported, matches ``notes()``.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, measured against the server's own record of when it last saw a note change rather than against ``Note/modification``.
    ///
    /// - Returns: The changed notes and the identifiers of the unchanged ones.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    public func notes(changedSince: Date) async throws -> NoteChanges {
        try requireCredentials()
        logger.debug("Fetching notes changed since \(changedSince)...")

        // A moment at or before the Unix epoch has no positive number of seconds to express it, and pruning before it would exclude nothing anyway, so the server is asked not to prune at all.
        let pruneBefore = changedSince.wholeSecondsSince1970 ?? 0
        let data = try await notesAPIPayload(for: "notes", queryItems: [URLQueryItem(name: "pruneBefore", value: String(pruneBefore))])
        let entries: [NoteEntry]

        do {
            entries = try jsonDecoder.decode([NoteEntry].self, from: data)
        } catch {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to decode the notes: \(error)")
        }

        var changed = [Note]()
        var unchanged = [Int]()

        for entry in entries {
            switch entry {
                case let .changed(note): changed.append(note)
                case let .unchanged(id): unchanged.append(id)
            }
        }

        return NoteChanges(changed: changed, unchanged: unchanged)
    }

    ///
    /// Look up the settings the notes app keeps for the authenticated user.
    ///
    /// These say where the app stores notes and which extension it gives a new one, which matters because notes are ordinary files: the folder is not a fixed name but a value derived from the account's locale by default, so anything which wants to reach notes over WebDAV rather than through ``notes()`` has to ask for it rather than assume it. See ``NotesSettings``.
    ///
    /// The same requirement and the same failure modes as ``notes()`` apply, since this is the same app's API.
    ///
    /// - Returns: The notes app's settings for the authenticated user.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry the settings.
    ///     - Any other error that might occur during retrieval.
    ///
    public func notesSettings() async throws -> NotesSettings {
        try requireCredentials()
        logger.debug("Fetching note settings...")

        let data = try await notesAPIPayload(for: "settings")

        do {
            return try jsonDecoder.decode(NotesSettings.self, from: data)
        } catch {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to decode the note settings: \(error)")
        }
    }

    ///
    /// Retrieve one page of the activity stream the server records for the authenticated user.
    ///
    /// Activities are what the server logs about everything happening in an account: files being created, changed and shared, calendar events being scheduled, security relevant events and whatever else an installed app contributes. They are provided by the server's bundled activity app, which is not necessarily installed or enabled. Whether it is available can be checked in advance via the ``Activity`` capability, e.g. `try await capabilities().contains(Activity.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/notFound``.
    ///
    /// The server never returns the whole stream at once, so this returns a single ``ActivityPage`` and leaves paging to the caller: request the next page by passing the previous page's ``ActivityPage/lastGiven`` as `since`, until a page comes back with no ``ActivityPage/items``. Detecting whether anything new happened instead is a matter of comparing ``ActivityPage/firstKnown`` against the value remembered from an earlier call, which is how this pairs with ``ServerEvent/activities``.
    ///
    /// Credentials are required: activities are user-scoped and the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Parameters:
    ///     - filter: The subset of the stream to retrieve. Beyond ``ActivityFilter/all``, ``ActivityFilter/own`` and ``ActivityFilter/others`` a server offers further, app-provided filters which can be discovered through ``activityFilters()``. Defaults to ``ActivityFilter/all``.
    ///     - since: The identifier of the activity to continue after, exclusively. Defaults to `0`, which starts at the beginning of the requested sort order.
    ///     - limit: How many activities to retrieve at most. Values are clamped to `1 ... 200`: the server caps the page size at two hundred regardless of what is asked for, and rejects a page size of zero or below with an internal error. Defaults to `50`, matching the server's own default.
    ///     - sort: The direction to walk the stream in. Defaults to ``ActivitySort/newestFirst``.
    ///     - previews: Whether to include the thumbnails of referenced files in ``ActivityItem/previews``. Defaults to `false`, matching the server's own default.
    ///     - objectType: The type of a single object to narrow the stream down to, e.g. `"files"`. Only effective together with `objectId`, and passing both selects ``ActivityFilter/object`` regardless of `filter`. Defaults to `nil`.
    ///     - objectId: The identifier of a single object to narrow the stream down to. Only effective together with `objectType`. Defaults to `nil`.
    ///
    /// - Returns: One page of activities in the order returned by the server, together with the cursors needed to continue.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the activity app is not available on the server or the requested filter does not exist.
    ///     - Any other error that might occur during retrieval.
    ///
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

    ///
    /// List the filters the server offers to narrow the activity stream down with.
    ///
    /// Filters are contributed by the server and its installed apps rather than being a fixed list, so this is how the identifiers accepted by the `filter` argument of ``activities(filter:since:limit:sort:previews:objectType:objectId:)`` beyond the well-known ones declared on ``ActivityFilter`` are discovered. Whether the server supports this is advertised under the ``Activity`` capability's `"filters-api"` entry.
    ///
    /// Credentials are required: the underlying OCS endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The available filters in the order returned by the server.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/notFound`` when the activity app is not available on the server.
    ///     - Any other error that might occur during retrieval.
    ///
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

    ///
    /// Set up a URL request specifically for Nextcloud OCS API interaction.
    ///
    /// Credentials are optional for this call.
    ///
    /// `queryItems` defaults to an empty array, so endpoints which are parameterized through the path alone are requested without naming it. Passing an empty array produces exactly the URL a call without any query would.
    ///
    /// - Parameters:
    ///     - path: The path relative to the OCS root, e.g. `"apps/activity/api/v2/activity/all"`.
    ///     - method: The HTTP method to use.
    ///     - queryItems: The query parameters to append, in the order they should appear.
    ///
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

    ///
    /// Set up a URL request specifically for the REST API of a server app which is not reachable through OCS.
    ///
    /// Apps commonly expose their own endpoints below `/index.php/apps/`, outside both the OCS root ``makeOCSRequest(for:method:queryItems:)`` targets and the WebDAV roots ``makeWebDAVRequest(for:method:)`` targets. The notes app is one of them, and this is what ``notes()`` is built on.
    ///
    /// Credentials are optional for this call, matching ``makeOCSRequest(for:method:queryItems:)``, because whether an app route requires them is up to the app. No `OCS-APIRequest` header is set, as the request does not go through OCS.
    ///
    /// `queryItems` defaults to an empty array, so endpoints which are parameterized through the path alone are requested without naming it. Passing an empty array produces exactly the URL a call without any query would.
    ///
    /// - Parameters:
    ///     - path: The path relative to the apps root (see ``Server/appsAddress``), e.g. `"notes/api/v1/notes"`.
    ///     - method: The HTTP method to use.
    ///     - queryItems: The query parameters to append, in the order they should appear.
    ///
    public func makeAppRequest(for path: String, method: Method, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let url = appsAddress.appendingCompatibility(path: path, directoryHint: .inferFromPath)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // The query is only assigned when there is one so that a request without query parameters produces a bare URL rather than one with a trailing question mark.
        if queryItems.isEmpty == false {
            components?.queryItems = queryItems
        }

        var request = makeRequest(for: components?.url ?? url, method: method)

        if let user, let password {
            let encodedCredentials = Data("\(user):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    ///
    /// Set up a URL request specifically for WebDAV interaction.
    ///
    /// The given `path` is resolved relative to the account's WebDAV files root (see ``Server/webDAVPathPrefix``, e.g. `"/remote.php/dav/files/<user>"`).
    ///
    /// Unlike ``makeOCSRequest(for:method:queryItems:)``, credentials are required for this call.
    ///
    /// - Throws: ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///
    public func makeWebDAVRequest(for path: String, method: Method) throws -> URLRequest {
        try makeWebDAVRequest(for: webDAVAddress.appendingCompatibility(path: path, directoryHint: .inferFromPath), method: method)
    }

    ///
    /// Poll the status of a login flow.
    ///
    /// - Parameters:
    ///     - endpoint: The URL to poll on.
    ///     - token: The unique token of the login flow to check the status of.
    ///
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

    ///
    /// Delete the app password this ``Server`` is currently authenticating with, ending the account's session on the server side.
    ///
    /// This targets the self-service `DELETE /ocs/v2.php/core/apppassword` endpoint: the server resolves which app password to revoke from the authenticated request itself, so no identifier is passed or needed.
    /// Because ``Server/user`` and ``Server/password`` are immutable, calling this does not by itself make this ``Server`` instance unusable; it is the caller's responsibility to discard the ``Server`` (and any persisted copy of ``Server/password``) once this call returns.
    ///
    /// A `401 Unauthorized` response means the app password was already invalid (e.g. revoked elsewhere) before this request could even reach the server; a `403 Forbidden` response means the session was not authenticated with an app password at all. Both, like any other non-success response, are surfaced as ``RainmakerError/unexpectedStatus(code:)`` rather than tolerated here: whether such failures should still be treated as an effective local sign-out is a decision left to the caller.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/unexpectedStatus(code:)`` for any non-success response.
    ///
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
