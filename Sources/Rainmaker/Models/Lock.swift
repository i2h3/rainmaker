// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Represents different kinds of item locks.
///
/// See the [files_lock](https://github.com/nextcloud/files_lock) server app for further information.
///
public enum Lock: Model {
    ///
    /// User manually locked the item.
    ///
    /// This corresponds to a `0` in the `nc:lock-owner-type`.
    ///
    /// - Parameters:
    ///     - owner: A user who owns the lock.
    ///     - time: Timestamp of the log creation time.
    ///     - timeOut: Time to live of the lock in seconds staring from the creation time. a value of 0 means the timeout is infinite. Client implementations should properly handle this specific value.
    ///
    case user(owner: User, time: Date, timeOut: Date)

    ///
    /// Collaboratively locked, in example while editing in Office or Text.
    ///
    /// This corresponds to a `1` in the `nc:lock-owner-type`.
    ///
    /// - Parameters:
    ///     - editor: App id of an app owned lock to allow clients to suggest joining the collaborative editing session through the web or direct editing.
    ///     - owner: A user who owns the lock.
    ///     - time: Timestamp of the log creation time.
    ///     - timeOut: Time to live of the lock in seconds staring from the creation time. a value of 0 means the timeout is infinite. Client implementations should properly handle this specific value.
    ///
    case app(editor: String, owner: User, time: Date, timeOut: Date)

    ///
    /// WebDAV lock identified by a lock token.
    ///
    /// The token itself is returned only on its creation by a `LOCK` request and not continously with every item property listing.
    ///
    /// This corresponds to a `2` in the `nc:lock-owner-type`.
    ///
    /// - Parameters:
    ///     - editor: App id of an app owned lock to allow clients to suggest joining the collaborative editing session through the web or direct editing.
    ///     - owner: A user who owns the lock.
    ///     - time: Timestamp of the log creation time.
    ///     - timeOut: Time to live of the lock in seconds staring from the creation time. a value of 0 means the timeout is infinite. Client implementations should properly handle this specific value.
    ///     
    case token(editor: String, owner: User, time: Date, timeOut: Date)
}
