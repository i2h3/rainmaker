// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The resolved WebSocket endpoint and the subset of requested subjects the server actually pushes.
///
/// ``ServerEventCoordinator/pushTarget(from:requested:accountAddress:)`` derives it from the ``PushNotifications`` capability, and the coordinator opens a ``PushNotificationsConnection`` to it while polling every requested ``ServerSubject`` it does not cover.
///
struct PushTarget {
    ///
    /// The `wss://` (or accepted `ws://`) endpoint to connect to, as checked by ``ServerEventCoordinator/isAcceptable(endpoint:accountAddress:)``.
    ///
    let endpoint: URL

    ///
    /// The requested subjects the server advertises over `notify_push`.
    ///
    let subjects: Set<ServerSubject>
}
