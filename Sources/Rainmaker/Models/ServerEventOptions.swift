// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Configures which server-side changes ``Serving/events(_:)`` observes and how often it polls.
///
/// The defaults observe every ``ServerSubject`` and poll every 30 seconds when the `notify_push` WebSocket is unavailable, matching the cadence the official Nextcloud clients use.
///
public struct ServerEventOptions: Sendable {
    ///
    /// The subjects to observe.
    ///
    /// Only the intersection of these with the subjects the server advertises under ``PushNotifications/type`` is delivered over the WebSocket; any remaining subject is polled instead.
    ///
    public var subjects: Set<ServerSubject>

    ///
    /// The interval in seconds at which subjects are polled while the WebSocket is unavailable, or for subjects the server does not push.
    ///
    public var pollInterval: TimeInterval

    ///
    /// The interval in seconds of the low-frequency backstop poll that runs even while the WebSocket is connected.
    ///
    /// The `notify_push` documentation recommends that clients keep polling occasionally as a best-effort safety net against missed pushes, which is what this interval governs.
    ///
    public var backstopPollInterval: TimeInterval

    ///
    /// Whether to opt into per-file identifiers by sending `listen notify_file_id` after authenticating, delivering them via ``ServerEvent/files(ids:)`` when the server supports it (`notify_push` 0.4 and later).
    ///
    public var listenFileIDs: Bool

    ///
    /// Whether to emit ``ServerEvent/connected`` immediately when the subscription starts so a client performs an initial fetch without waiting for the first change.
    ///
    public var emitConnectedOnStart: Bool

    ///
    /// Create a new set of options.
    ///
    /// - Parameters:
    ///     - subjects: The subjects to observe. Defaults to all of them.
    ///     - pollInterval: The polling interval in seconds used when the WebSocket is unavailable. Defaults to 30.
    ///     - backstopPollInterval: The backstop polling interval in seconds used while the WebSocket is connected. Defaults to 900.
    ///     - listenFileIDs: Whether to request per-file identifiers. Defaults to `false`.
    ///     - emitConnectedOnStart: Whether to emit ``ServerEvent/connected`` on subscription. Defaults to `true`.
    ///
    public init(subjects: Set<ServerSubject> = Set(ServerSubject.allCases), pollInterval: TimeInterval = 30, backstopPollInterval: TimeInterval = 900, listenFileIDs: Bool = false, emitConnectedOnStart: Bool = true) {
        self.subjects = subjects
        self.pollInterval = pollInterval
        self.backstopPollInterval = backstopPollInterval
        self.listenFileIDs = listenFileIDs
        self.emitConnectedOnStart = emitConnectedOnStart
    }
}
