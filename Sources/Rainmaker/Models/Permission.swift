// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Different kinds of permissions associated with an ``Item``.
///
/// See [Nextcloud server documentation for developers](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/WebDAV/properties.html#permissions) for further details and reference.
///
public enum Permission: Character, Model {
    ///
    /// Permission to create a new directory within a directory.
    ///
    case createDirectory = "K"

    ///
    /// Permission to create a new file within a directory.
    ///
    case createFile = "C"

    ///
    /// Permission to delete the item.
    ///
    case delete = "D"

    ///
    /// Permission to move the item to another directory.
    ///
    case move = "V"

    ///
    /// The item is a mount point, e.g. an external storage or a share mounted into the account's files.
    ///
    case mounted = "M"

    ///
    /// Permission to rename the item.
    ///
    case rename = "N"

    ///
    /// Permission to read the item, which the server abbreviates as `G` for get.
    ///
    case read = "G"

    ///
    /// Permission to share the item with others.
    ///
    case share = "R"

    ///
    /// The item is shared with the account rather than owned by it.
    ///
    case shared = "S"

    ///
    /// Permission to update the content of a file.
    ///
    case write = "W"

    var description: String {
        switch self {
            case .createDirectory:
                "createDirectory"
            case .createFile:
                "createFile"
            case .delete:
                "delete"
            case .move:
                "move"
            case .mounted:
                "mounted"
            case .rename:
                "rename"
            case .read:
                "read"
            case .share:
                "share"
            case .shared:
                "shared"
            case .write:
                "write"
        }
    }

    ///
    /// Parse a string of multiple permission letters into a set of ``Permission`` values.
    ///
    static func parse(_ compound: String) throws -> Set<Permission> {
        var permissions: Set<Permission> = []

        for character in compound {
            guard let permission = Self(rawValue: character) else {
                throw RainmakerError.responseDecodingFailed(reason: "Unknown permission character: \(character)")
            }

            permissions.insert(permission)
        }

        return permissions
    }
}
