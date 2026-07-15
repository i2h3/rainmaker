// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A category of server-side change a client can observe through ``Serving/events(_:)``.
///
/// The raw values deliberately match the strings the server lists under ``PushNotifications/type``, so the subjects observable over the WebSocket are simply the intersection of the requested subjects with the advertised ones, without any mapping table.
///
public enum ServerSubject: String, Sendable, CaseIterable, Hashable {
    ///
    /// The notifications queued for the user changed, retrievable via ``Serving/notifications()``.
    ///
    /// Nextcloud Talk mentions and calls also surface here as notifications with the `spreed` app identifier.
    ///
    case notifications

    ///
    /// The user's files changed.
    ///
    case files

    ///
    /// The user's activity stream changed.
    ///
    case activities

    ///
    /// The ``ServerEvent`` a poll tick emits for this subject.
    ///
    /// Polling cannot know which concrete items changed, so the file event carries no identifiers; that detail is only available over the WebSocket via ``ServerEvent/files(ids:)``.
    ///
    var event: ServerEvent {
        switch self {
            case .notifications:
                .notifications
            case .files:
                .files(ids: nil)
            case .activities:
                .activities
        }
    }
}
