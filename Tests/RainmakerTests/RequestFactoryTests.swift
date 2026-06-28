// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// Tests for the public request factory methods.
///
/// These build a `URLRequest` without performing any network call, so the requests are asserted on directly
/// and no mock session or response fixtures are required.
///
@Suite("Request Factories") struct RequestFactoryTests {
    let serverAddress = URL(string: "http://localhost/")!

    ///
    /// Expected value of the `Authorization` header for the default `admin`/`admin` credentials.
    ///
    var expectedBasicAuthorization: String {
        "Basic \(Data("admin:admin".utf8).base64EncodedString())"
    }

    func makeServer(user: String? = "admin", password: String? = "admin") -> Server {
        Server(address: serverAddress, password: password, user: user, userAgent: "RainmakerTests")
    }

    @Test("OCS Request When Authenticated")
    func ocsRequestAuthenticated() throws {
        let server = makeServer()
        let request = try server.makeOCSRequest(for: "cloud/capabilities", method: .get)

        #expect(request.url == server.OCSAddress.appendingCompatibility(path: "cloud/capabilities", directoryHint: .inferFromPath))
        #expect(request.httpMethod == "GET")

        let headers = request.allHTTPHeaderFields
        #expect(headers?["OCS-APIRequest"] == "true")
        #expect(headers?["Accept"] == "application/json")
        #expect(headers?["User-Agent"] == "RainmakerTests")
        #expect(headers?["Authorization"] == expectedBasicAuthorization)
    }

    @Test("OCS Request When Unauthenticated")
    func ocsRequestUnauthenticated() throws {
        let server = makeServer(user: nil, password: nil)
        let request = try server.makeOCSRequest(for: "cloud/capabilities", method: .get)

        // Credentials are optional for OCS: the request is still built, just without an `Authorization` header.
        #expect(request.allHTTPHeaderFields?["OCS-APIRequest"] == "true")
        #expect(request.allHTTPHeaderFields?["Authorization"] == nil)
    }

    @Test("WebDAV Request When Authenticated")
    func webDAVRequestAuthenticated() throws {
        let server = makeServer()
        let request = try server.makeWebDAVRequest(for: "Documents/Readme.md", method: .propfind)

        #expect(request.url == server.webDAVAddress.appendingCompatibility(path: "Documents/Readme.md", directoryHint: .inferFromPath))
        #expect(request.httpMethod == "PROPFIND")

        let headers = request.allHTTPHeaderFields
        #expect(headers?["Accept"] == "application/xml")
        #expect(headers?["Content-Type"] == "application/xml")
        #expect(headers?["User-Agent"] == "RainmakerTests")
        #expect(headers?["Authorization"] == expectedBasicAuthorization)
    }

    @Test("WebDAV Request Requires Credentials")
    func webDAVRequestRequiresCredentials() throws {
        let server = makeServer(user: nil, password: nil)

        #expect(throws: RainmakerError.credentialsRequired) {
            try server.makeWebDAVRequest(for: "Documents/Readme.md", method: .propfind)
        }
    }

    @Test("WebDAV Request Preserves Special Characters")
    func webDAVRequestPreservesSpecialCharacters() throws {
        let server = makeServer()
        let request = try server.makeWebDAVRequest(for: "Special Characters/:/Readme.md", method: .propfind)

        // The path is appended (and percent-encoded) consistently, so decoding it again yields the original input.
        let path = try #require(request.url?.compatibilityPath(percentEncoded: false))
        #expect(path == "/remote.php/dav/files/admin/Special Characters/:/Readme.md")
    }
}
