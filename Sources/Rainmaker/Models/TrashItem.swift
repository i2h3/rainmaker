// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Represents an item in the server's trash bin, directories and files alike.
///
/// Trashed items are listed through ``Serving/trash()`` and can be restored to their original location with ``Serving/restore(_:)-(String)`` or removed altogether by emptying the trash bin with ``Serving/emptyTrash()``.
///
public struct TrashItem: Model, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    ///
    /// The opaque identifier of the trashed item within the trash bin.
    ///
    /// This is the last path component of ``href``, e.g. `"Readme.md.d1700000000"`, and is the value to pass to ``Serving/restore(_:)-(String)``.
    ///
    public let id: String

    ///
    /// The path of the item relative to the trash bin root.
    ///
    public let path: String

    ///
    /// The full path of the item on the server.
    ///
    public let href: URL

    ///
    /// The original name of the item before it was moved to the trash bin.
    ///
    public let name: String

    ///
    /// The original location of the item relative to the user's root directory before it was moved to the trash bin.
    ///
    public let originalLocation: String

    ///
    /// The date the item was moved to the trash bin.
    ///
    public let deletion: Date

    ///
    /// Whether the trashed item is a directory or a file.
    ///
    public let isDirectory: Bool

    ///
    /// The size of the item in bytes.
    ///
    /// In case of a directory, this is the total size of all content. It is `nil` when the server does not report a size.
    ///
    public let size: UInt64?

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a trashed item.
    ///
    public var description: String {
        name
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a trashed item.
    ///
    public var debugDescription: String {
        path
    }
}
