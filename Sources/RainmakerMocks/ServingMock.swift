import Foundation
import Rainmaker

///
/// A hand-written mock implementation of ``Serving`` for use in tests.
///
public final class ServingMock: Serving, @unchecked Sendable {
    // MARK: - Serving

    public let address: URL
    public let password: String
    public let user: String

    init(address: URL, password: String, user: String) {
        self.address = address
        self.password = password
        self.user = user
    }

    public func content(at path: String) async throws -> [Item] {
        mockedReturnValueOfContentAtPath[path] ?? []
    }

    // MARK: - Mock

    private var mockedReturnValueOfContentAtPath: [String: [Item]] = [:]

    public func mockReturnValueOfContentAtPath(_ items: [Item], for path: String) {
        mockedReturnValueOfContentAtPath[path] = items
    }
}
