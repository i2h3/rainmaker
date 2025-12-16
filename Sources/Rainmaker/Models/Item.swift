import Foundation

///
/// Represents a file system item, directories and files alike.
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

    ///
    /// Structured information about related comments.
    ///
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

    ///
    /// Custom encoding implementation.
    ///
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
