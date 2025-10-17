import Foundation
import Testing
@testable import Rainmaker

@Test func listRootFolderContent() async throws {
    let server = Server(address: URL(string: "http://localhost:8081")!, password: "admin", user: "admin")
    let items = try await server.content(at: "/")

    #expect(items.count == 10, "Expected the folder itself and its 9 default children!")
    #expect(items.filter { $0.isDirectory }.count == 4, "Expected the folder itself and its 3 subfolders!")
}
