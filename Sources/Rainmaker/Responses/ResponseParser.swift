import Foundation

///
/// Parse WebDAV XML responses to own types.
///
public final class ResponseParser {
    static func items(from data: Data) throws -> [Item] {
        let root = try XMLTreeBuilder(data: data).parse()
        let responses = root.elements(forName: "d:response")

        let items = try responses.map { response in
            try parseItem(from: response)
        }

        return items
    }

    // MARK: - Private

    private static func parseItem(from response: Element) throws -> Item {
        guard let hrefString = response.firstElement(forName: "d:href")?.stringValue, let href = URL(string: hrefString) else {
            throw RainmakerError.responseDecodingFailed("Failed to get href.")
        }

        let propstats = response.elements(forName: "d:propstat")

        guard let propstat = propstats.first(where: { candidate in
            candidate.firstElement(forName: "d:status")?.stringValue == "HTTP/1.1 200 OK"
        }) else {
            throw RainmakerError.responseDecodingFailed("Failed to find propstat element with status code 200 for: \(href.absoluteString)")
        }

        guard let prop = propstat.firstElement(forName: "d:prop") else {
            throw RainmakerError.responseDecodingFailed("Failed to find prop element for: \(href.absoluteString)")
        }

        // MARK: creation

        guard let creationString = prop.firstElement(forName: "d:creationdate")?.stringValue, let creationDate = ISO8601DateFormatter().date(from: creationString) else {
            throw RainmakerError.responseDecodingFailed("Failed to get creation date for: \(href.absoluteString)")
        }

        // MARK: modification

        guard let lastModifiedString = prop.firstElement(forName: "d:getlastmodified")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get last modified date for: \(href.absoluteString)")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"

        guard let modification = formatter.date(from: lastModifiedString) else {
            throw RainmakerError.responseDecodingFailed("Failed to parse last modified date: \(lastModifiedString)")
        }

        // MARK: entityTag

        guard let entityTag = prop.firstElement(forName: "d:getetag")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get entity tag for: \(href.absoluteString)")
        }

        // MARK: size

        guard let sizeString = prop.firstElement(forName: "oc:size")?.stringValue, let sizeValue = UInt64(sizeString) else {
            throw RainmakerError.responseDecodingFailed("Failed to get size for: \(href.absoluteString)")
        }

        // MARK: displayName

        guard let displayName = prop.firstElement(forName: "d:displayname")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get display name for: \(href.absoluteString)")
        }

        // MARK: isDirectory

        let isDirectory = prop.firstElement(forName: "d:resourcetype")?.elements(forName: "d:collection").isEmpty == false

        // MARK: contentType

        let contentType: String?

        if isDirectory {
            contentType = nil
        } else {
            guard let type = prop.firstElement(forName: "d:getcontenttype")?.stringValue else {
                throw RainmakerError.responseDecodingFailed("Failed to get content type name for: \(href.absoluteString)")
            }

            contentType = type
        }

        // MARK: id

        guard let id = prop.firstElement(forName: "oc:id")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get id for: \(href.absoluteString)")
        }

        // MARK: instanceId

        guard let instanceId = prop.firstElement(forName: "oc:fileid")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get instance id for: \(href.absoluteString)")
        }

        // MARK: permissions

        guard let permissionsString = prop.firstElement(forName: "oc:permissions")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get permissions for: \(href.absoluteString)")
        }

        let permissions = try Permission.parse(permissionsString)

        // MARK: isEncrypted

        let isEncrypted = prop.firstElement(forName: "oc:is-encrypted") != nil

        // MARK: isFavorite

        let isFavorite = prop.firstElement(forName: "oc:favorite")?.stringValue == "1"

        // MARK: isMountRoot

        let isMountRoot = prop.firstElement(forName: "nc:is-mount-root")?.stringValue == "true"

        // MARK: comments

        let path = prop.firstElement(forName: "oc:comments-href")?.stringValue

        let commentCount = UInt(prop.firstElement(forName: "oc:comments-count")?.stringValue ?? "") ?? 0
        let unreadCommentCount = UInt(prop.firstElement(forName: "oc:comments-unread")?.stringValue ?? "") ?? 0

        let comments = Item.Comments(path: path, count: commentCount, unread: unreadCommentCount)

        // MARK: owner

        guard let ownerId = prop.firstElement(forName: "oc:owner-id")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get owner id for: \(href.absoluteString)")
        }

        guard let ownerDisplayName = prop.firstElement(forName: "oc:owner-display-name")?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get owner display name for: \(href.absoluteString)")
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
                throw RainmakerError.responseDecodingFailed("Failed to get upload time for: \(href.absoluteString)")
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
                        throw RainmakerError.responseDecodingFailed("Failed to get lock editor for: \(href.absoluteString)")
                    }

                    lock = .app(editor: lockOwnerEditor, owner: user, time: time, timeOut: timeOut)
                case "2":
                    guard let lockOwnerEditor else {
                        throw RainmakerError.responseDecodingFailed("Failed to get lock editor for: \(href.absoluteString)")
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
            owner: owner,
            permissions: permissions,
            size: sizeValue,
            upload: upload
        )
    }
}
