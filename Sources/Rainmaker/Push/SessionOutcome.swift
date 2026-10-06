// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The outcome of one WebSocket session, telling ``ServerEventCoordinator`` how to proceed.
///
/// It is what the session the coordinator runs over a ``PushNotificationsConnection`` reduces that connection's ``PushNotificationsConnection/Failure`` to, so that the coordinator only counts what its retry and fallback decisions depend on.
///
enum SessionOutcome {
    ///
    /// The server rejected authentication, so the socket should be retried a bounded number of times (``ServerEventCoordinator/maximumAuthenticationAttempts``) before falling back to polling.
    ///
    case authenticationRejected

    ///
    /// The socket dropped.
    ///
    /// `wasAuthenticated` is `true` when it had connected successfully first, which resets the reconnection backoff and the count of consecutive connection failures. When it is `false` the socket never got as far as authenticating, which ``ServerEventCoordinator`` counts towards ``ServerEventCoordinator/maximumConnectionFailures`` before falling back to polling.
    ///
    case disconnected(wasAuthenticated: Bool)
}
