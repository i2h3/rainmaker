// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About flattening an ``ActivityRichText`` back into plain text.
///
/// No fixtures or network are involved: every case decodes the two-element array the server serializes a rich text as and calls ``ActivityRichText/resolved()`` on it.
///
@Suite("Activity Rich Text") struct ActivityRichTextTests {
    ///
    /// Decode a rich text from the literal payload shape the server sends.
    ///
    private func makeRichText(_ payload: String) throws -> ActivityRichText {
        try JSONDecoder().decode(ActivityRichText.self, from: Data(payload.utf8))
    }

    @Test("Resolves Placeholders")
    func resolvesPlaceholders() throws {
        let richText = try makeRichText(#"["You changed {file}",{"file":{"type":"file","id":"72","name":"Readme.md","path":"Readme.md"}}]"#)

        #expect(richText.resolved() == "You changed Readme.md")
    }

    @Test("Does Not Expand A Name Which Looks Like A Placeholder")
    func doesNotExpandSubstitutedText() throws {
        // A name is chosen by whoever created the file, calendar or tag an activity is about, so it can contain braces. Substituted text must never be scanned again, whatever order the parameters happen to be visited in.
        let richText = try makeRichText(#"["{a} {b}",{"a":{"type":"highlight","id":"1","name":"{b}"},"b":{"type":"highlight","id":"2","name":"Bob"}}]"#)

        #expect(richText.resolved() == "{b} Bob")
    }

    @Test("Is Independent Of Parameter Order")
    func isDeterministic() throws {
        // Dictionaries have no guaranteed order, so resolving the same rich text repeatedly has to keep producing the same string.
        let richText = try makeRichText(#"["{a} {b} {c}",{"a":{"type":"highlight","id":"1","name":"{b}"},"b":{"type":"highlight","id":"2","name":"{c}"},"c":{"type":"highlight","id":"3","name":"end"}}]"#)
        let results = Set((0 ..< 50).map { _ in richText.resolved() })

        #expect(results == ["{b} {c} end"])
    }

    @Test("Leaves An Unknown Placeholder In Place")
    func leavesUnknownPlaceholder() throws {
        let richText = try makeRichText(#"["{known} and {unknown}",{"known":{"type":"highlight","id":"1","name":"this"}}]"#)

        #expect(richText.resolved() == "this and {unknown}")
    }

    @Test("Tolerates An Unterminated Brace")
    func toleratesUnterminatedBrace() throws {
        let richText = try makeRichText(#"["{known} and {oops",{"known":{"type":"highlight","id":"1","name":"this"}}]"#)

        #expect(richText.resolved() == "this and {oops")
    }

    @Test("Returns The Template When There Are No Parameters")
    func returnsTemplateWithoutParameters() throws {
        // The server serializes an empty parameter dictionary as an empty array rather than as an empty object.
        let richText = try makeRichText(#"["",[]]"#)

        #expect(richText.template == "")
        #expect(richText.parameters.isEmpty)
        #expect(richText.resolved() == "")

        let braced = try makeRichText(#"["{file} stays",[]]"#)
        #expect(braced.resolved() == "{file} stays")
    }

    @Test("Resolves Repeated And Adjacent Placeholders")
    func resolvesRepeatedPlaceholders() throws {
        let richText = try makeRichText(#"["{a}{a} {a}",{"a":{"type":"highlight","id":"1","name":"x"}}]"#)

        #expect(richText.resolved() == "xx x")
    }
}
