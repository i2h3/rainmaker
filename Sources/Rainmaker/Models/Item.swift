import Foundation

///
/// Represents a file system item, directories and files alike.
///
public struct Item: Model {
    ///
    /// The full path of the item on the server.
    ///
    public let href: URL

    ///
    /// Whether the item is a directory or file.
    ///
    public let isDirectory: Bool

    ///
    /// The name as in the file system.
    ///
    public let name: String

    ///
    /// The size of the item in bytes.
    /// This is `nil` for directories.
    ///
    public let size: UInt64?
}
