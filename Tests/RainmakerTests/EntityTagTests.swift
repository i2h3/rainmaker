// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About turning the `ETag` header of a notes response into the bare entity tag handed out, and that tag back into the value of an `If-None-Match` or `If-Match` header.
///
/// These tests need neither a server nor response fixtures because both conversions are pure functions of the string.
///
@Suite("Entity Tag") struct EntityTagTests {
    @Test("Strips the quotes of a strong tag")
    func unquotesStrongTag() {
        #expect(#""c649e503de046daca1b998c2e52b2a94""#.unquotedEntityTag == "c649e503de046daca1b998c2e52b2a94")
    }

    @Test("Strips the weakness marker and the quotes of a weak tag")
    func unquotesWeakTag() {
        // A proxy compressing the response may weaken the tag, while the server compares a conditional request against the strong tag it computed, so only the bare value can still produce a not modified answer.
        #expect(#"W/"c649e503de046daca1b998c2e52b2a94""#.unquotedEntityTag == "c649e503de046daca1b998c2e52b2a94")
    }

    @Test("Leaves a bare tag as it is")
    func keepsBareTag() {
        #expect("c649e503".unquotedEntityTag == "c649e503")
    }

    @Test("Ignores surrounding whitespace")
    func trimsWhitespace() {
        #expect(#"  "c649e503" "#.unquotedEntityTag == "c649e503")
    }

    @Test("Leaves a lone quote alone")
    func keepsLoneQuote() {
        // A single quote is not a pair of quotes around an empty tag, so nothing is stripped from it.
        #expect(#"""#.unquotedEntityTag == #"""#)
    }

    @Test("Quotes a bare tag")
    func quotesBareTag() {
        #expect("c649e503".quotedEntityTag == #""c649e503""#)
    }

    @Test("Does not quote a quoted tag twice")
    func keepsQuotedTag() {
        #expect(#""c649e503""#.quotedEntityTag == #""c649e503""#)
    }

    @Test("Turns a weak tag into the strong header value the server compares against")
    func roundTripsWeakTag() {
        #expect(#"W/"c649e503""#.unquotedEntityTag.quotedEntityTag == #""c649e503""#)
    }
}
