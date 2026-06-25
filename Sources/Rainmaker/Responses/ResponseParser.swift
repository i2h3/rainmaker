// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Parse WebDAV XML responses to own types.
///
enum ResponseParser {
    static func items(from data: Data, webDAVPathPrefix: String) throws -> [Item] {
        let root = try XMLTreeBuilder(data: data).parse()
        let responses = root.elements(forName: "d:response")

        return try responses.map { response in
            try parseItem(from: response, webDAVPathPrefix: webDAVPathPrefix)
        }
    }

    static func trashItems(from data: Data, trashbinPathPrefix: String) throws -> [TrashItem] {
        let root = try XMLTreeBuilder(data: data).parse()
        let responses = root.elements(forName: "d:response")

        return try responses.compactMap { response in
            try parseTrashItem(from: response, trashbinPathPrefix: trashbinPathPrefix)
        }
    }

    // MARK: - Private

    private static func parseItem(from response: Element, webDAVPathPrefix: String) throws -> Item {
        guard let hrefString = response.firstElement(forName: "d:href")?.stringValue, let href = URL(string: hrefString) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get href.")
        }

        guard href.path().hasPrefix(webDAVPathPrefix) else {
            throw RainmakerError.responseDecodingFailed(reason: "href does not have expected prefix!")
        }

        let path = String(href.path(percentEncoded: false).dropFirst(webDAVPathPrefix.count))

        let propstats = response.elements(forName: "d:propstat")

        guard let propstat = propstats.first(where: { candidate in
            candidate.firstElement(forName: "d:status")?.stringValue == "HTTP/1.1 200 OK"
        }) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to find propstat element with status code 200 for: \(href.absoluteString)")
        }

        guard let prop = propstat.firstElement(forName: "d:prop") else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to find prop element for: \(href.absoluteString)")
        }

        // MARK: creation

        guard let creationString = prop.firstElement(forName: "nc:creation_time")?.stringValue, let creationTimeInterval = TimeInterval(creationString) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get creation time for: \(href.absoluteString)")
        }

        let creationDate = Date(timeIntervalSince1970: creationTimeInterval)

        // MARK: modification

        guard let lastModifiedString = prop.firstElement(forName: "d:getlastmodified")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get last modified date for: \(href.absoluteString)")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"

        guard let modification = formatter.date(from: lastModifiedString) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to parse last modified date: \(lastModifiedString)")
        }

        // MARK: entityTag

        guard let entityTag = prop.firstElement(forName: "d:getetag")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get entity tag for: \(href.absoluteString)")
        }

        // MARK: size

        guard let sizeString = prop.firstElement(forName: "oc:size")?.stringValue, let sizeValue = UInt64(sizeString) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get size for: \(href.absoluteString)")
        }

        // MARK: displayName

        guard let displayName = prop.firstElement(forName: "d:displayname")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get display name for: \(href.absoluteString)")
        }

        // MARK: isDirectory

        let isDirectory = prop.firstElement(forName: "d:resourcetype")?.elements(forName: "d:collection").isEmpty == false

        // MARK: contentType

        let contentType: String?

        if isDirectory {
            contentType = nil
        } else {
            guard let type = prop.firstElement(forName: "d:getcontenttype")?.stringValue else {
                throw RainmakerError.responseDecodingFailed(reason: "Failed to get content type name for: \(href.absoluteString)")
            }

            contentType = type
        }

        // MARK: id

        guard let id = prop.firstElement(forName: "oc:id")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get id for: \(href.absoluteString)")
        }

        // MARK: instanceId

        guard let instanceId = prop.firstElement(forName: "oc:fileid")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get instance id for: \(href.absoluteString)")
        }

        // MARK: permissions

        guard let permissionsString = prop.firstElement(forName: "oc:permissions")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get permissions for: \(href.absoluteString)")
        }

        let permissions = try Permission.parse(permissionsString)

        // MARK: isEncrypted

        let isEncrypted = prop.firstElement(forName: "oc:is-encrypted") != nil

        // MARK: isFavorite

        let isFavorite = prop.firstElement(forName: "oc:favorite")?.stringValue == "1"

        // MARK: isMountRoot

        let isMountRoot = prop.firstElement(forName: "nc:is-mount-root")?.stringValue == "true"

        // MARK: comments

        let commentsPath = prop.firstElement(forName: "oc:comments-href")?.stringValue

        let commentCount = UInt(prop.firstElement(forName: "oc:comments-count")?.stringValue ?? "") ?? 0
        let unreadCommentCount = UInt(prop.firstElement(forName: "oc:comments-unread")?.stringValue ?? "") ?? 0

        let comments = Item.Comments(path: commentsPath, count: commentCount, unread: unreadCommentCount)

        // MARK: quota

        var quota: Quota?

        if let usedBytesString = prop.firstElement(forName: "d:quota-used-bytes")?.stringValue,
           let availableBytesString = prop.firstElement(forName: "d:quota-available-bytes")?.stringValue
        {
            if let usedBytes = Int64(usedBytesString), let availableBytes = Int64(availableBytesString) {
                let available = AvailableQuota(availableBytes)
                quota = Quota(available: available, used: usedBytes)
            }
        }

        // MARK: owner

        guard let ownerId = prop.firstElement(forName: "oc:owner-id")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get owner id for: \(href.absoluteString)")
        }

        guard let ownerDisplayName = prop.firstElement(forName: "oc:owner-display-name")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get owner display name for: \(href.absoluteString)")
        }

        let owner = User(id: ownerId, displayName: ownerDisplayName)

        // MARK: hasPreview

        let hasPreview = prop.firstElement(forName: "nc:has-preview")?.stringValue == "true"

        // MARK: isHidden

        let isHidden = prop.firstElement(forName: "nc:hidden")?.stringValue == "true"

        // MARK: upload

        let upload: Date?

        if isDirectory {
            upload = nil
        } else {
            guard let uploadString = prop.firstElement(forName: "nc:upload_time")?.stringValue else {
                throw RainmakerError.responseDecodingFailed(reason: "Failed to get upload time for: \(href.absoluteString)")
            }

            upload = Date(timeIntervalSince1970: TimeInterval(uploadString) ?? 0)
        }

        // MARK: lock

        let lockState = prop.firstElement(forName: "nc:lock")?.stringValue
        let lockOwner = prop.firstElement(forName: "nc:lock-owner")?.stringValue
        let lockOwnerDisplayName = prop.firstElement(forName: "nc:lock-owner-displayname")?.stringValue
        let lockOwnerEditor = prop.firstElement(forName: "nc:lock-owner-editor")?.stringValue
        let lockOwnerType = prop.firstElement(forName: "nc:lock-owner-type")?.stringValue
        let lockTimeString = prop.firstElement(forName: "nc:lock-time")?.stringValue
        let lockTimeOutString = prop.firstElement(forName: "nc:lock-timeout")?.stringValue

        var lock: Lock?

        if lockState == "1", let lockOwnerDisplayName, let lockOwner, let lockTimeString, let lockTime = Double(lockTimeString), let lockTimeOutString, let timeOut = Double(lockTimeOutString) {
            let time = Date(timeIntervalSince1970: lockTime)
            let timeOut = Date(timeIntervalSince1970: lockTime + timeOut)
            let user = User(id: lockOwner, displayName: lockOwnerDisplayName)

            switch lockOwnerType {
                case "0":
                    lock = .user(owner: user, time: time, timeOut: timeOut)
                case "1":
                    guard let lockOwnerEditor else {
                        throw RainmakerError.responseDecodingFailed(reason: "Failed to get lock editor for: \(href.absoluteString)")
                    }

                    lock = .app(editor: lockOwnerEditor, owner: user, time: time, timeOut: timeOut)
                case "2":
                    guard let lockOwnerEditor else {
                        throw RainmakerError.responseDecodingFailed(reason: "Failed to get lock editor for: \(href.absoluteString)")
                    }

                    lock = .token(editor: lockOwnerEditor, owner: user, time: time, timeOut: timeOut)
                default:
                    break
            }
        }

        return Item(
            comments: comments,
            contentType: contentType,
            creation: creationDate,
            entityTag: entityTag,
            hasPreview: hasPreview,
            href: href,
            id: id,
            instanceId: instanceId,
            isDirectory: isDirectory,
            isEncrypted: isEncrypted,
            isFavorite: isFavorite,
            isHidden: isHidden,
            isMountRoot: isMountRoot,
            lock: lock,
            modification: modification,
            name: displayName,
            quota: quota,
            owner: owner,
            path: path,
            permissions: permissions,
            size: sizeValue,
            upload: upload
        )
    }

    private static func parseTrashItem(from response: Element, trashbinPathPrefix: String) throws -> TrashItem? {
        guard let hrefString = response.firstElement(forName: "d:href")?.stringValue, let href = URL(string: hrefString) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get href.")
        }

        guard href.path().hasPrefix(trashbinPathPrefix) else {
            throw RainmakerError.responseDecodingFailed(reason: "href does not have expected prefix!")
        }

        let path = String(href.path(percentEncoded: false).dropFirst(trashbinPathPrefix.count))

        // The trash bin root itself is part of the listing. It carries no trash metadata and is skipped.
        if path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty {
            return nil
        }

        let propstats = response.elements(forName: "d:propstat")

        guard let propstat = propstats.first(where: { candidate in
            candidate.firstElement(forName: "d:status")?.stringValue == "HTTP/1.1 200 OK"
        }) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to find propstat element with status code 200 for: \(href.absoluteString)")
        }

        guard let prop = propstat.firstElement(forName: "d:prop") else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to find prop element for: \(href.absoluteString)")
        }

        // MARK: name

        // Without a trash file name this response does not describe a trashed item (e.g. the trash bin root) and is skipped.
        guard let name = prop.firstElement(forName: "nc:trashbin-filename")?.stringValue else {
            return nil
        }

        // MARK: originalLocation

        guard let originalLocation = prop.firstElement(forName: "nc:trashbin-original-location")?.stringValue else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get original location for: \(href.absoluteString)")
        }

        // MARK: deletion

        guard let deletionString = prop.firstElement(forName: "nc:trashbin-deletion-time")?.stringValue, let deletionInterval = TimeInterval(deletionString) else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get deletion time for: \(href.absoluteString)")
        }

        let deletion = Date(timeIntervalSince1970: deletionInterval)

        // MARK: isDirectory

        let isDirectory = prop.firstElement(forName: "d:resourcetype")?.elements(forName: "d:collection").isEmpty == false

        // MARK: size

        let size = (prop.firstElement(forName: "oc:size")?.stringValue).flatMap { UInt64($0) } ?? (prop.firstElement(forName: "d:getcontentlength")?.stringValue).flatMap { UInt64($0) }

        return TrashItem(
            id: href.lastPathComponent,
            path: path,
            href: href,
            name: name,
            originalLocation: originalLocation,
            deletion: deletion,
            isDirectory: isDirectory,
            size: size
        )
    }
}
