// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About converting a modification date into the value of the `X-OC-Mtime` header.
///
/// These tests need neither a server nor response fixtures because the conversion is a pure function of the date.
///
@Suite("Whole Seconds Since 1970") struct WholeSecondsSince1970Tests {
    @Test("Converts an ordinary date")
    func ordinaryDate() throws {
        let seconds = try #require(Date(timeIntervalSince1970: 1_700_000_000).wholeSecondsSince1970)
        #expect(seconds == 1_700_000_000)
    }

    @Test("Truncates towards the past")
    func fractionalDate() throws {
        // Rounding down keeps the reported modification date from ever appearing newer than the file actually is.
        let seconds = try #require(Date(timeIntervalSince1970: 1_700_000_000.9).wholeSecondsSince1970)
        #expect(seconds == 1_700_000_000)
    }

    @Test("Converts a date far in the future without trapping")
    func distantFuture() throws {
        // The interval of `Date.distantFuture` exceeds the range of a 32 bit `Int`, which is what `Int` is on some of the supported platforms.
        // Converting it there used to terminate the process, and `Tests/RainmakerTests/UploadTests.swift` reaches this exact value.
        let seconds = try #require(Date.distantFuture.wholeSecondsSince1970)
        #expect(seconds == 64_092_211_200)
    }

    @Test("Rejects a date at the Unix epoch")
    func epoch() {
        #expect(Date(timeIntervalSince1970: 0).wholeSecondsSince1970 == nil)
    }

    @Test("Rejects a date before the Unix epoch")
    func distantPast() {
        #expect(Date.distantPast.wholeSecondsSince1970 == nil)
    }

    @Test("Rejects a date without a finite interval", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteDate(_ interval: Double) {
        #expect(Date(timeIntervalSince1970: interval).wholeSecondsSince1970 == nil)
    }
}
