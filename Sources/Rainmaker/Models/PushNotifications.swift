// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's push notifications capability, advertised when the `notify_push` app is installed and its high-performance backend is configured.
///
/// Nextcloud can push change signals to connected clients over a WebSocket instead of requiring them to poll. When the `notify_push` app is set up the server advertises this object under the `notify_push` key, which is why ``key`` is `"notify_push"`. Its presence, together with a WebSocket ``Endpoints/websocket`` address, is what lets ``Serving/events(_:)`` prefer the WebSocket over polling.
///
/// When the high-performance backend is not configured the whole `notify_push` key is absent from the capabilities, so a lookup via ``CapabilitySet/get(_:)`` yields `nil` and clients fall back to polling.
/// All fields are kept optional so that a server which omits one of them still decodes successfully.
///
public struct PushNotifications: Capability {
    public static let key = "notify_push"

    ///
    /// The subjects the server pushes, e.g. `["files", "activities", "notifications"]`.
    ///
    /// These map onto ``ServerSubject`` by raw value, so the set of subjects that can be observed over the WebSocket is the intersection of this list with the subjects a client requests.
    ///
    public let type: [String]?

    ///
    /// The connection endpoints the push service advertises.
    ///
    public let endpoints: Endpoints?

    ///
    /// The endpoints nested under the `notify_push` capability.
    ///
    public struct Endpoints: Decodable, Sendable {
        ///
        /// The WebSocket URL to connect to, e.g. `wss://cloud.example.com/push/ws`.
        ///
        /// This is absent when the high-performance backend is not wired up, in which case clients fall back to polling.
        ///
        public let websocket: URL?

        ///
        /// The pre-authentication token endpoint for clients which hold a session but not the raw credentials.
        ///
        /// It is decoded for completeness and reserved for a future addition; ``Serving/events(_:)`` authenticates with the ``Server/user`` and ``Server/password`` it already holds and therefore does not need it.
        ///
        public let preAuth: URL?

        private enum CodingKeys: String, CodingKey {
            case websocket
            case preAuth = "pre_auth"
        }
    }
}
