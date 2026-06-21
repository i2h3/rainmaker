// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single entry in the apps navigation a Nextcloud server advertises for the authenticated user.
///
/// These are the server apps (e.g. Files, Photos, Activity) which a client can surface in its own
/// navigation. The ``href`` is a path relative to the server address.
///
public struct NavigationItem: Model, Identifiable, Decodable {
    ///
    /// The unique identifier of the app, e.g. `"files"`.
    ///
    public let id: String

    ///
    /// The sort order determining the position of the app in the navigation.
    ///
    public let order: Int

    ///
    /// The path of the app relative to the server address, e.g. `"/apps/files/"`.
    ///
    public let href: String

    ///
    /// The path of the app icon relative to the server address, e.g. `"/apps/files/img/app.svg"`.
    ///
    public let icon: String

    ///
    /// The type of the navigation entry, e.g. `"link"`.
    ///
    public let type: String

    ///
    /// The human readable display name of the app, e.g. `"Files"`.
    ///
    public let name: String

    ///
    /// The identifier of the app providing this entry, e.g. `"files"`.
    ///
    public let app: String

    ///
    /// Whether this entry is currently active.
    ///
    public let isActive: Bool

    ///
    /// The number of unread items associated with the app.
    ///
    public let unread: UInt

    ///
    /// The CSS classes the server associates with this entry. Empty when there are none.
    ///
    public let classes: String

    ///
    /// Whether this app is the default app for the user.
    ///
    public let isDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case order
        case href
        case icon
        case type
        case name
        case app
        case isActive = "active"
        case unread
        case classes
        case isDefault = "default"
    }
}
