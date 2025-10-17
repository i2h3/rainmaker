///
/// Represents a file system item.
///
public struct Item: Model {
    ///
    /// Whether the item is a directory or not.
    ///
    let isDirectory: Bool

    ///
    /// The name as in the file system.
    ///
    let name: String
}
