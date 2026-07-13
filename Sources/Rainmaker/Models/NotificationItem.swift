// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single notification currently queued for the authenticated user on the server.
///
/// Notifications are listed through ``Serving/notifications()``. Whether the notifications app which provides them is available at all can be checked in advance via the ``Notifications`` capability, e.g. `try await capabilities().contains(Notifications.self)`.
///
/// This models the stable, human-readable fields of a notification. The rich-text variants (`subjectRich`, `messageRich` and their parameters) and the interactive `actions` returned by the server are intentionally not modelled yet, as acting on notifications is out of scope.
///
public struct NotificationItem: Model, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the notification, unique per user.
    ///
    /// This corresponds to the server's `notification_id`.
    ///
    public let id: Int

    ///
    /// The identifier of the app which emitted the notification, e.g. `"admin_notifications"`.
    ///
    public let app: String

    ///
    /// The name of the user the notification is addressed to.
    ///
    public let user: String

    ///
    /// The moment the notification was created on the server.
    ///
    /// This corresponds to the server's `datetime` field, an ISO 8601 timestamp.
    ///
    public let creation: Date

    ///
    /// The type of the object the notification refers to, e.g. `"admin_notifications"`.
    ///
    /// Together with ``objectId`` this identifies the subject the notification is about.
    ///
    public let objectType: String

    ///
    /// The identifier of the object the notification refers to.
    ///
    /// Together with ``objectType`` this identifies the subject the notification is about.
    ///
    public let objectId: String

    ///
    /// The human-readable subject line of the notification.
    ///
    public let subject: String

    ///
    /// The human-readable message body of the notification. Empty when the notification carries no body.
    ///
    public let message: String

    ///
    /// The link a client should open when the notification is activated. Empty when the notification is not actionable through a link.
    ///
    public let link: String

    ///
    /// The address of the notification icon. Empty when the notification carries no icon.
    ///
    /// This is kept as a string rather than a `URL` because the server may return an empty value.
    ///
    public let icon: String

    private enum CodingKeys: String, CodingKey {
        case id = "notification_id"
        case app
        case user
        case creation = "datetime"
        case objectType = "object_type"
        case objectId = "object_id"
        case subject
        case message
        case link
        case icon
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a notification.
    ///
    public var description: String {
        subject
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a notification.
    ///
    public var debugDescription: String {
        "#\(id) (\(app)): \(subject)"
    }
}
