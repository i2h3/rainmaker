// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's trash bin capability, exposing whether items can be restored from or permanently deleted out of the trash bin.
///
/// On Nextcloud, the trash bin is provided by the bundled "Deleted files" app (`files_trashbin`). When that app is enabled, the server advertises these flags inside the `files` capability object, which is why ``key`` is `"files"`.
///
/// Both flags are only advertised to authenticated clients; an anonymous capabilities request does not contain them.
/// They are kept optional so that a server which does not advertise a particular flag still decodes successfully.
///
public struct Trashing: Capability {
    public static let key = "files"

    ///
    /// Whether items can be restored from the trash bin.
    ///
    /// This corresponds to the Nextcloud `files.undelete` capability.
    ///
    public let undelete: Bool?

    ///
    /// Whether items can be permanently deleted out of the trash bin.
    ///
    /// This corresponds to the Nextcloud `files.delete_from_trash` capability.
    ///
    public let deleteFromTrash: Bool?

    private enum CodingKeys: String, CodingKey {
        case undelete
        case deleteFromTrash = "delete_from_trash"
    }
}
