// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's notifications capability, advertised when the notifications app is installed and enabled.
///
/// On Nextcloud, user notifications are provided by the bundled "Notifications" app (`notifications`). When that app is available the server advertises this object under the `notifications` key, which is why ``key`` is `"notifications"`. Its mere presence is the signal a client needs before calling ``Serving/notifications()``: check it with `try await capabilities().contains(Notifications.self)`.
///
/// The object is only advertised to authenticated clients; an anonymous capabilities request does not contain it.
/// All fields are kept optional so that a server which omits one of them still decodes successfully.
///
public struct Notifications: Capability {
    public static let key = "notifications"

    ///
    /// The OCS endpoints the server supports, e.g. `["list", "get", "delete", "delete-all", ...]`.
    ///
    /// The `"list"` entry is the one backing ``Serving/notifications()``.
    ///
    public let ocsEndpoints: [String]?

    ///
    /// The push notification capabilities the server supports, e.g. `["devices", "object-data", "delete"]`.
    ///
    public let push: [String]?

    ///
    /// The channels through which administrators can emit notifications, e.g. `["ocs", "cli"]`.
    ///
    public let adminNotifications: [String]?

    private enum CodingKeys: String, CodingKey {
        case ocsEndpoints = "ocs-endpoints"
        case push
        case adminNotifications = "admin-notifications"
    }
}
