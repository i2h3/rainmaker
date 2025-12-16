import Foundation

///
/// Represents a Nextcloud instance to interact with.
///
public protocol Serving: Sendable {
    ///
    /// The base address of the Nextcloud instance.
    ///
    var address: URL { get }

    ///
    /// The app password to use for authentication.
    ///
    var password: String { get }

    ///
    /// The user to authenticate as.
    ///
    var user: String { get }

    ///
    /// Returns a list of items in the folder specified by the given path.
    ///
    func content(at path: String) async throws -> [Item]
}
