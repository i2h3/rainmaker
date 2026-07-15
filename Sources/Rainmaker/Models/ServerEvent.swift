// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A hint that something changed on the server, delivered by ``Serving/events(_:)``.
///
/// Every case is a hint to re-fetch, never a payload: this mirrors how the `notify_push` WebSocket works and lets the polling fallback synthesize the very same hints on a timer, so a client consumes ``Serving/events(_:)`` identically regardless of which transport is active.
/// A client reacts to an event by re-fetching the relevant state itself, for example calling ``Serving/notifications()`` in response to ``notifications``.
///
public enum ServerEvent: Sendable, Equatable {
    ///
    /// The stream connected or reconnected, so every subscribed subject should be re-fetched to reconcile anything missed while offline.
    ///
    /// This is emitted once when the subscription starts (unless disabled via ``ServerEventOptions/emitConnectedOnStart``) and again after each successful WebSocket (re)connection.
    ///
    case connected

    ///
    /// The notifications queued for the user changed, retrievable via ``Serving/notifications()``.
    ///
    case notifications

    ///
    /// The user's files changed.
    ///
    /// When the change arrived over the WebSocket and the server reported the affected file identifiers, `ids` carries them; otherwise it is `nil`, including for every poll tick.
    ///
    case files(ids: [Int]?)

    ///
    /// The user's activity stream changed.
    ///
    case activities

    ///
    /// A push type Rainmaker does not model natively, forwarded verbatim for future or third-party subjects.
    ///
    /// `type` is the leading token of the WebSocket frame and `body` is the remainder when the frame carried one.
    ///
    case custom(type: String, body: String?)
}
