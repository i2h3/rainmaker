// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About reading the HTTP dates of the `Last-Modified` header and of the WebDAV `getlastmodified` property.
///
/// These tests need neither a server nor response fixtures because the conversion is a pure function of the string.
///
@Suite("HTTP Date") struct HTTPDateTests {
    @Test("Reads a date in GMT")
    func readsGMT() throws {
        let date = try #require(Date(httpDate: "Tue, 14 Nov 2023 22:13:20 GMT"))
        #expect(date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Reads the canonical value of the recorded fixtures")
    func readsCanonicalValue() throws {
        // The fixture canonicalizer writes this in place of every recorded Last-Modified header of the notes app, so it has to stay readable.
        let date = try #require(Date(httpDate: "Sat, 01 Jan 2000 00:00:00 GMT"))
        #expect(date == Date(timeIntervalSince1970: 946_684_800))
    }

    @Test("Reads a date with a numeric offset")
    func readsNumericOffset() throws {
        let date = try #require(Date(httpDate: "Tue, 14 Nov 2023 23:13:20 +0100"))
        #expect(date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Reads the epoch the WebDAV fixtures are canonicalized to")
    func readsEpoch() throws {
        let date = try #require(Date(httpDate: "Thu, 01 Jan 1970 00:00:00 GMT"))
        #expect(date == Date(timeIntervalSince1970: 0))
    }

    @Test("Rejects what is not an HTTP date", arguments: ["", "yesterday", "1700000000", "2023-11-14T22:13:20Z"])
    func rejectsGarbage(_ string: String) {
        #expect(Date(httpDate: string) == nil)
    }
}
