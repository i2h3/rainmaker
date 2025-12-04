import Foundation

///
/// Represents a file system item, directories and files alike.
/// 
/// > To Do: Add properties: https://docs.nextcloud.com/server/stable/developer_manual/client_apis/WebDAV/basic.html
///
public struct Item: Model, Identifiable {
    ///
    /// Information about comments related to an Item.
    ///
    public struct Comments: Model {
        ///
        /// The relative path on the server.
        ///
        let path: String?

        ///
        /// The number of comments in total.
        ///
        let count: UInt

        ///
        /// The number of unread comments.
        ///
        let unread: UInt
    }

    public let comments: Comments

    ///
    /// The MIME type of the item.
    ///
    /// This is available for files only. For directories, this is always `nil`.
    ///
    public let contentType: String?

    ///
    /// Creation date.
    ///
    public let creation: Date

    ///
    /// Opaque identifier for a particular version and state of the item.
    ///
    public let entityTag: String

    ///
    /// Whether a preview for the item is available or not.
    ///
    public let hasPreview: Bool

    ///
    /// The full path of the item on the server.
    ///
    public let href: URL

    ///
    /// The globally unique file identifier namespaced by the server identifier.
    ///
    public let id: String

    ///
    /// The unique identifier of the item specific on the server it is located on.
    ///
    public let instanceId: String

    ///
    /// Whether the item is a directory or file.
    ///
    public let isDirectory: Bool

    ///
    /// Whether the item is end-to-end encrypted or not.
    ///
    public let isEncrypted: Bool

    ///
    /// Whether this item is a favorite or not.
    ///
    public let isFavorite: Bool

    ///
    /// Whether the item should be hidden from the user or not.
    ///
    public let isHidden: Bool

    ///
    /// Whether the item is a mount root or not.
    /// In example: shared folders are a mount root.
    ///
    public let isMountRoot: Bool

    ///
    /// Whether this item is locked or not and in what way.
    ///
    public let lock: Lock?

    ///
    /// Latest modification date.
    ///
    public let modification: Date

    ///
    /// The name as in the file system.
    ///
    public let name: String

    ///
    /// The owner of this item.
    ///
    public let owner: User

    ///
    /// A collection of letters with specific semantics for each.
    ///
    public let permissions: Set<Permission>

    ///
    /// The size of the item in bytes.
    ///
    /// In case of a directory, this is the total size of all content.
    ///
    public let size: UInt64

    ///
    /// Time of upload.
    ///
    /// This is `nil` for directories.
    ///
    public let upload: Date?

    // MARK: - Parsing

    ///
    /// Initialize from an individual XML response element as contained in a `PROPSTAT` request.
    ///
    init(response: XMLElement) throws {
        guard let href = URL(string: response.elements(forName: "d:href").first?.stringValue ?? "") else {
            throw RainmakerError.responseDecodingFailed("Failed to get href.")
        }

        self.href = href
        let propstats = response.elements(forName: "d:propstat")

        guard let propstat = propstats.first(where: { candidate in
            guard let element = candidate.elements(forName: "d:status").first else {
                return false
            }

            guard element.stringValue == "HTTP/1.1 200 OK" else {
                return false
            }

            return true
        }) else {
            throw RainmakerError.responseDecodingFailed("Failed to find propstat element with status code 200 for: \(href.absoluteString)")
        }

        guard let prop = propstat.elements(forName: "d:prop").first else {
            throw RainmakerError.responseDecodingFailed("Failed to find prop element for: \(href.absoluteString)")
        }

        // MARK: creation

        guard let creationString = prop.elements(forName: "d:creationdate").first?.stringValue, let creationDate = ISO8601DateFormatter().date(from: creationString) else {
            throw RainmakerError.responseDecodingFailed("Failed to get creation date for: \(href.absoluteString)")
        }

        self.creation = creationDate

        // MARK: modification

        // Wed, 15 Oct 2025 07:19:31 GMT

        guard let lastModifiedString = prop.elements(forName: "d:getlastmodified").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get last modified date for: \(href.absoluteString)")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"

        guard let modification = formatter.date(from: lastModifiedString) else {
            throw RainmakerError.responseDecodingFailed("Failed to parse last modified date: \(lastModifiedString)")
        }

        self.modification = modification

        // MARK: entityTag

        guard let entityTag = prop.elements(forName: "d:getetag").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get entity tag for: \(href.absoluteString)")
        }

        self.entityTag = entityTag

        // MARK: size

        guard let size = prop.elements(forName: "oc:size").first?.stringValue, let sizeValue = UInt64(size) else {
            throw RainmakerError.responseDecodingFailed("Failed to get size for: \(href.absoluteString)")
        }

        self.size = sizeValue

        // MARK: displayName

        guard let displayName = prop.elements(forName: "d:displayname").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get display name for: \(href.absoluteString)")
        }

        self.name = displayName

        // MARK: isDirectory

        self.isDirectory = prop.elements(forName: "d:resourcetype").first?.elements(forName: "d:collection").isEmpty == false

        // MARK: contentType

        if self.isDirectory {
            self.contentType = nil
        } else {
            guard let contentType = prop.elements(forName: "d:getcontenttype").first?.stringValue else {
                throw RainmakerError.responseDecodingFailed("Failed to get content type name for: \(href.absoluteString)")
            }

            self.contentType = contentType
        }

        // MARK: id

        guard let id = prop.elements(forName: "oc:id").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get id for: \(href.absoluteString)")
        }

        self.id = id

        // MARK: instanceId

        guard let instanceId = prop.elements(forName: "oc:fileid").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get instance id for: \(href.absoluteString)")
        }

        self.instanceId = instanceId

        // MARK: permissions

        guard let permissionsString = prop.elements(forName: "oc:permissions").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get permissions for: \(href.absoluteString)")
        }

        self.permissions = try Permission.parse(permissionsString)

        // MARK: isEncrypted

        self.isEncrypted = prop.elements(forName: "oc:is-encrypted").first?.stringValue != nil

        // MARK: isFavorite

        self.isFavorite = prop.elements(forName: "oc:favorite").first?.stringValue == "1"

        // MARK: isMountRoot

        self.isMountRoot = prop.elements(forName: "oc:is-mount-root").first?.stringValue == "true"

        // MARK: comments

        var commentCount: UInt = 0
        var unreadCommentCount: UInt = 0

        let path = prop.elements(forName: "oc:comments-href").first?.stringValue

        if let rawCommentCount = prop.elements(forName: "oc:comments-count").first?.stringValue {
            if let parsedCommentCount = UInt(rawCommentCount){
                commentCount = parsedCommentCount
            }
        }

        if let rawUnreadCommentCount = prop.elements(forName: "oc:comments-unread").first?.stringValue {
            if let parsedUnreadCommentCount = UInt(rawUnreadCommentCount){
                unreadCommentCount = parsedUnreadCommentCount
            }
        }

        self.comments = Comments(path: path, count: commentCount, unread: unreadCommentCount)

        // MARK: owner

        guard let id = prop.elements(forName: "oc:owner-id").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get owner id for: \(href.absoluteString)")
        }

        guard let displayName = prop.elements(forName: "oc:owner-display-name").first?.stringValue else {
            throw RainmakerError.responseDecodingFailed("Failed to get owner display name for: \(href.absoluteString)")
        }

        self.owner = User(id: id, displayName: displayName)

        // MARK: hasPreview

        self.hasPreview = prop.elements(forName: "nc:has-preview").first?.stringValue == "true"

        // MARK: isHidden

        self.isHidden = prop.elements(forName: "nc:hidden").first?.stringValue == "true"

        // MARK: upload

        if self.isDirectory {
            self.upload = nil
        } else {
            guard let uploadString = prop.elements(forName: "nc:upload_time").first?.stringValue else {
                throw RainmakerError.responseDecodingFailed("Failed to get upload time for: \(href.absoluteString)")
            }

            self.upload = Date(timeIntervalSince1970: TimeInterval(uploadString) ?? 0)
        }

        // MARK: lock

        let lockState = prop.elements(forName: "nc:lock").first?.stringValue
        let lockOwner = prop.elements(forName: "nc:lock-owner").first?.stringValue
        let lockOwnerDisplayName = prop.elements(forName: "nc:lock-owner-displayname").first?.stringValue
        let lockOwnerEditor = prop.elements(forName: "nc:lock-owner-editor").first?.stringValue
        let lockOwnerType = prop.elements(forName: "nc:lock-owner-type").first?.stringValue
        let lockTimeString = prop.elements(forName: "nc:lock-time").first?.stringValue
        let lockTimeOutString = prop.elements(forName: "nc:lock-timeout").first?.stringValue

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

        self.lock = lock
    }

    // MARK: - Encodable

    enum CodingKeys: CodingKey {
        case comments
        case contentType
        case creation
        case entityTag
        case hasPreview
        case href
        case id
        case instanceId
        case isDirectory
        case isEncrypted
        case isFavorite
        case isHidden
        case isMountRoot
        case lock
        case modification
        case name
        case owner
        case permissions
        case size
        case upload
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.comments, forKey: .comments)
        try container.encodeIfPresent(self.contentType, forKey: .contentType)
        try container.encode(self.creation, forKey: .creation)
        try container.encode(self.entityTag, forKey: .entityTag)
        try container.encode(self.hasPreview, forKey: .hasPreview)
        try container.encode(self.href, forKey: .href)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.instanceId, forKey: .instanceId)
        try container.encode(self.isDirectory, forKey: .isDirectory)
        try container.encode(self.isEncrypted, forKey: .isEncrypted)
        try container.encode(self.isFavorite, forKey: .isFavorite)
        try container.encode(self.isHidden, forKey: .isHidden)
        try container.encode(self.isMountRoot, forKey: .isMountRoot)
        try container.encodeIfPresent(self.lock, forKey: .lock)
        try container.encode(self.modification, forKey: .modification)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.owner, forKey: .owner)

        let joinedPermissions = self.permissions.map(\.description).sorted()
        try container.encode(joinedPermissions, forKey: .permissions)

        try container.encode(self.size, forKey: .size)
        try container.encodeIfPresent(self.upload, forKey: .upload)
    }
}
