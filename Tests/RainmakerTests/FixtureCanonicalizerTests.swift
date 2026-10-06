// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// Tests for ``FixtureCanonicalizer`` which normalizes recorded responses before they are written as fixtures.
///
/// These run entirely in memory and require neither a network nor a live server.
///
@Suite("Fixture Canonicalizer") struct FixtureCanonicalizerTests {
    let canonicalizer = FixtureCanonicalizer(liveServerAddress: URL(string: "http://localhost:54540/")!)

    ///
    /// Canonicalize a body as if it had been the response to a request for the given path.
    ///
    /// The path matters because ``FixtureCanonicalizer`` scopes some of its replacements to the API they describe, so a rule can only be exercised through a request it actually applies to.
    ///
    func canonicalize(_ string: String, pathExtension: String, path: String = "/remote.php/dav/files/admin/") -> String {
        let requestURL = URL(string: "http://localhost:54540\(path)")!
        let result = canonicalizer.canonicalizedBody(Data(string.utf8), pathExtension: pathExtension, requestURL: requestURL)

        return String(data: result, encoding: .utf8) ?? ""
    }

    ///
    /// Serialize headers as if they had been the response to a request for the given path and return the resulting lines.
    ///
    /// The path matters for the same reason it does in ``canonicalize(_:pathExtension:path:)``: which header fields are preserved depends on the API the response belongs to.
    ///
    func headerLines(statusCode: Int, headerFields: [AnyHashable: Any], path: String = "/remote.php/dav/files/admin/") throws -> [String] {
        let requestURL = URL(string: "http://localhost:54540\(path)")!
        let data = canonicalizer.headersText(statusCode: statusCode, headerFields: headerFields, requestURL: requestURL)
        let text = try #require(String(data: data, encoding: .utf8))

        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    @Test("Rewrites the live origin to the canonical one")
    func rewritesOrigin() {
        let body = "{\"server\":\"http://localhost:54540/remote.php\"}"
        #expect(canonicalize(body, pathExtension: "json") == "{\"server\":\"http://localhost/remote.php\"}")
    }

    @Test("Redacts the volatile WebDAV fields")
    func redactsVolatileFields() {
        let body = """
        <d:getlastmodified>Fri, 19 Dec 2025 14:18:33 GMT</d:getlastmodified>
        <d:getetag>"69455eb955bf5"</d:getetag>
        <oc:id>00000002ocb3twjyt9mh</oc:id>
        <oc:fileid>2</oc:fileid>
        <oc:comments-href>/remote.php/dav/comments/files/2</oc:comments-href>
        """

        let result = canonicalize(body, pathExtension: "xml")

        #expect(result.contains("<d:getlastmodified>Thu, 01 Jan 1970 00:00:00 GMT</d:getlastmodified>"))
        #expect(result.contains("<d:getetag>\"00000000000000000000000000000000\"</d:getetag>"))
        #expect(result.contains("<oc:id>00000000000000000000000000000000</oc:id>"))
        #expect(result.contains("<oc:fileid>0</oc:fileid>"))
        #expect(result.contains("<oc:comments-href>/remote.php/dav/comments/files/0</oc:comments-href>"))
    }

    @Test("Redacts login tokens and app passwords")
    func redactsTokens() {
        let body = "{\"token\": \"abc123\", \"appPassword\": \"secret\", \"login\": \"http://localhost:54540/login/v2/flow/XYZ789\"}"
        let result = canonicalize(body, pathExtension: "json", path: "/index.php/login/v2")

        #expect(result.contains("\"token\": \"REDACTED\""))
        #expect(result.contains("\"appPassword\": \"REDACTED\""))
        #expect(result.contains("http://localhost/login/v2/flow/REDACTED"))
    }

    @Test("Redacts login tokens in escaped login URLs")
    func redactsEscapedLoginURLTokens() {
        let body = "{\"login\":\"http:\\/\\/localhost:54540\\/login\\/v2\\/flow\\/XYZ789\"}"
        let result = canonicalize(body, pathExtension: "json", path: "/index.php/login/v2")

        #expect(result.contains("\\/login\\/v2\\/flow\\/REDACTED"))
        #expect(result.contains("XYZ789") == false)
    }

    @Test("Leaves login secrets alone outside the login flow")
    func leavesLoginSecretsScoped() {
        let body = "{\"token\": \"abc123\", \"appPassword\": \"secret\"}"
        let result = canonicalize(body, pathExtension: "json")

        // These names are only secrets in the login flow. Redacting them everywhere would rewrite an unrelated field which happens to share a name, which is exactly what the Talk conversation token used to suffer from.
        #expect(result.contains("\"token\": \"abc123\""))
        #expect(result.contains("\"appPassword\": \"secret\""))
    }

    @Test("Redacts the volatile conversation fields but keeps the token")
    func redactsConversationFields() {
        let body = "{\"token\":\"oypsiy6j\",\"lastActivity\":1788879440,\"avatarVersion\":\"b0135871\",\"lastMessage\":{\"timestamp\":1788879440}}"
        let result = canonicalize(body, pathExtension: "json", path: "/ocs/v2.php/apps/spreed/api/v4/room")

        #expect(result.contains("\"lastActivity\": 1700000000"))
        #expect(result.contains("\"timestamp\": 1700000000"))
        #expect(result.contains("\"avatarVersion\": \"00000000\""))

        // The token addresses a conversation in every further request, and the fixture directory of its avatar is named after it, so it has to survive verbatim.
        #expect(result.contains("\"token\":\"oypsiy6j\""))
    }

    @Test("Redacts the Talk signaling key")
    func redactsSignalingKey() {
        let body = "{\"hello-v2-token-key\": \"-----BEGIN PUBLIC KEY-----\\nMFkwEw==\\n-----END PUBLIC KEY-----\\n\"}"
        let result = canonicalize(body, pathExtension: "json", path: "/ocs/v2.php/cloud/capabilities")

        // The key is generated per installation, and its name is unique enough to be replaced everywhere rather than only under the Talk API.
        #expect(result.contains("\"hello-v2-token-key\": \"REDACTED\""))
    }

    @Test("Redacts the login moments and the quota of the current user")
    func redactsCurrentUserFields() {
        let body = #"{"ocs":{"data":{"id":"admin","firstLoginTimestamp":1788879000,"lastLoginTimestamp":1788879440,"lastLogin":1788879440000,"quota":{"free":-3,"used":5242880,"total":-3,"relative":12.34,"quota":-3},"displayname":"admin"}}}"#
        let result = canonicalize(body, pathExtension: "json", path: "/ocs/v2.php/cloud/user")

        #expect(result.contains("\"firstLoginTimestamp\": 946684800,"))
        #expect(result.contains("\"lastLoginTimestamp\": 946684800,"))
        #expect(result.contains("\"lastLogin\": 946684800000,"))
        #expect(result.contains("\"free\": 0,"))
        #expect(result.contains("\"used\": 0,"))
        #expect(result.contains("\"total\": 0,"))
        #expect(result.contains("\"relative\": 0,"))

        // The quota setting itself and the fields the client decodes are stable and stay as recorded.
        #expect(result.contains("\"quota\":-3}"))
        #expect(result.contains("\"id\":\"admin\""))
        #expect(result.contains("\"displayname\":\"admin\""))
    }

    @Test("Leaves quota-like fields alone outside the account details")
    func leavesCurrentUserFieldsScoped() {
        let body = #"{"used":5242880,"total":10485760,"lastLogin":1788879440000}"#
        let result = canonicalize(body, pathExtension: "json", path: "/ocs/v2.php/apps/notes/api/v1.4/notes")

        // These names are generic enough to mean something else in another API, which is why the rules only apply to the account details.
        #expect(result == body)
    }

    @Test("Redacts the volatile note entity tags")
    func redactsNoteEntityTags() {
        let body = #"[{"id":86,"modified":1700000000,"etag":"c649e503de046daca1b998c2e52b2a94"}]"#
        let result = canonicalize(body, pathExtension: "json")

        #expect(result.contains(#""etag": "00000000000000000000000000000000""#))

        // The identifier and the modification date of a note are deliberately left as recorded, because the tests assert on the latter and rely on the former telling notes apart.
        #expect(result.contains(#""id":86"#))
        #expect(result.contains(#""modified":1700000000"#))
    }

    @Test("Leaves binary bodies untouched")
    func leavesBinaryUntouched() {
        let body = "http://localhost:54540 should not be rewritten in binary"
        let result = canonicalize(body, pathExtension: "bin")
        #expect(result == body)
    }

    @Test("Serializes headers with the status line and only the allowlisted fields")
    func serializesHeaders() throws {
        let headers: [AnyHashable: Any] = [
            "Content-Type": "application/xml; charset=utf-8",
            "Date": "Fri, 19 Dec 2025 14:18:33 GMT",
            "Server": "nginx",
        ]

        let lines = try headerLines(statusCode: 207, headerFields: headers)

        #expect(lines.first == "HTTP/1.1 207 Multi-Status")
        #expect(lines.contains("Content-Type: application/xml; charset=utf-8"))
        #expect(lines.contains { $0.hasPrefix("Date") } == false)
        #expect(lines.contains { $0.hasPrefix("Server") } == false)
    }

    @Test("Keeps the notes sync headers with canonical values")
    func keepsNotesHeaders() throws {
        let headers: [AnyHashable: Any] = [
            "Content-Type": "application/json; charset=utf-8",
            "Date": "Tue, 06 Oct 2026 10:00:00 GMT",
            "ETag": "\"c649e503de046daca1b998c2e52b2a94\"",
            "Last-Modified": "Tue, 06 Oct 2026 10:00:00 GMT",
            "X-Notes-API-Versions": "0.2, 1.3, 1.4",
            "X-Notes-Chunk-Cursor": "1791280800-1791280799-98",
            "X-Notes-Chunk-Pending": "1",
        ]

        let lines = try headerLines(statusCode: 200, headerFields: headers, path: "/index.php/apps/notes/api/v1/notes")

        // The listing reports what to continue from in its headers, so those have to survive, with the values differing per deployment and per moment replaced by fixed ones which still read as a quoted tag, an HTTP date and a cursor.
        #expect(lines == [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json; charset=utf-8",
            "ETag: \"00000000000000000000000000000000\"",
            "Last-Modified: Sat, 01 Jan 2000 00:00:00 GMT",
            "X-Notes-API-Versions: 0.2, 1.3, 1.4",
            "X-Notes-Chunk-Cursor: 946684800-946684800-0",
            "X-Notes-Chunk-Pending: 1",
        ])
    }

    @Test("Leaves out the notes sync headers a notes response does not send")
    func leavesOutAbsentNotesHeaders() throws {
        let headers: [AnyHashable: Any] = [
            "Content-Type": "application/json; charset=utf-8",
            "X-Notes-API-Versions": "0.2, 1.3, 1.4",
        ]

        let lines = try headerLines(statusCode: 200, headerFields: headers, path: "/index.php/apps/notes/api/v1/settings")

        // A canonical value only replaces a header which was recorded, so a response without one does not gain it.
        #expect(lines == ["HTTP/1.1 200 OK", "Content-Type: application/json; charset=utf-8", "X-Notes-API-Versions: 0.2, 1.3, 1.4"])
    }

    @Test("Drops the entity tag and modification date outside the notes app")
    func dropsSyncHeadersElsewhere() throws {
        let headers: [AnyHashable: Any] = [
            "Content-Type": "application/xml; charset=utf-8",
            "ETag": "\"69455eb955bf5\"",
            "Last-Modified": "Fri, 19 Dec 2025 14:18:33 GMT",
        ]

        let lines = try headerLines(statusCode: 200, headerFields: headers, path: "/remote.php/dav/files/admin/Readme.md")

        // WebDAV sends both headers as well, but nothing reads them from there, and keeping them would make every recording churn.
        #expect(lines == ["HTTP/1.1 200 OK", "Content-Type: application/xml; charset=utf-8"])
    }

    @Test("Names the reason of a failed precondition")
    func reasonPhraseOfPreconditionFailed() throws {
        let lines = try headerLines(statusCode: 412, headerFields: [:], path: "/index.php/apps/notes/api/v1/notes/1")

        #expect(lines == ["HTTP/1.1 412 Precondition Failed"])
    }
}
