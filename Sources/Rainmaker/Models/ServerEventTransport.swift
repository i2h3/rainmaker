// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// How ``Server/events(_:)`` learns about server-side changes, chosen through ``ServerEventOptions/transport``.
///
/// Both transports deliver the same ``ServerEvent`` re-fetch hints, so the choice only affects how promptly they arrive and what the stream costs while it runs, not how a consumer handles them.
/// The raw values are the names the command line utility's `watch --transport` option accepts.
///
public enum ServerEventTransport: String, Sendable, Hashable, CaseIterable {
    ///
    /// Prefer the `notify_push` WebSocket when the server advertises it in its ``PushNotifications`` capability and the platform supports it, and poll otherwise.
    ///
    /// This is the default. On watchOS it always polls, because the system only grants WebSocket connections to apps in narrow circumstances, such as an active audio streaming session, as Apple's technote TN3135 on low-level networking on watchOS describes.
    /// It also polls for a while after the WebSocket repeatedly fails to connect, see ``Server/events(_:)``.
    ///
    case automatic

    ///
    /// Only poll every subject at ``ServerEventOptions/pollInterval``, without ever looking up the server's capabilities or opening a WebSocket.
    ///
    /// This suits a consumer that only needs a periodic re-fetch hint, or one running where a long-lived socket is unwanted, such as a short-lived extension. Because polling sends no requests of its own, a stream polling this way does not notice credentials the server rejects; the consumer learns about them from the requests it makes in response to the hints.
    ///
    case polling
}
