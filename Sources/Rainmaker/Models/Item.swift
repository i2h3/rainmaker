import Foundation

///
/// Represents a file system item.
///
public struct Item: Model {
    ///
    /// Whether the item is a directory or not.
    ///
    public let isDirectory: Bool

    ///
    /// The name as in the file system.
    ///
    public let name: String

    ///
    /// The size of the item in bytes.
    ///
    public let size: UInt64?

    ///
    /// The fully qualified URL of the item.
    ///
    public let url: URL
}
