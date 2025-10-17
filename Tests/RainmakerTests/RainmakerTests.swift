import Foundation
import Testing
@testable import Rainmaker

@Suite("Listing Tests") struct ListingTests {
    let server: any Serving

    init() throws {
        server = Server(address: URL(string: "http://localhost:8081")!, password: "admin", user: "admin")
    }

    @Test("List Root Folder Content") func listRootFolderContent() async throws {
        let items = try await server.content(at: "/")

        #expect(items.count == 9, "Expected the 9 default children!")
        #expect(items.filter { $0.isDirectory }.count == 3, "Expected the 3 subfolders!")
    }

    @Test("List Documents Folder Content") func listDocumentsFolderContent() async throws {
        let items = try await server.content(at: "/Documents")

        #expect(items.count == 4, "Expected the 4 default children!")
        #expect(items.filter { $0.isDirectory }.count == 0, "Expected the 0 subfolders!")
    }
}
