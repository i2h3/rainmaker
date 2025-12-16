// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Different kinds of permissions associated with items.
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

    case delete = "D"
    case move = "V"
    case mounted = "M"
    case rename = "N"
    case read = "G"
    case share = "R"
    case shared = "S"
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
                throw RainmakerError.responseDecodingFailed("Unknown permission character: \(character)")
            }

            permissions.insert(permission)
        }

        return permissions
    }
}
