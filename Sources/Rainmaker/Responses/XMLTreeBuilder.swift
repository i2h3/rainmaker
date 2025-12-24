// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// Builds an in-memory element tree from XML data using Foundation's XMLParser.
final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var root: Element?
    private var stack: [Element] = []

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() throws -> Element {
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "Failed to parse XML."
            throw RainmakerError.responseDecodingFailed(reason: reason)
        }

        guard let root else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to get root element of document.")
        }

        return root
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName qName: String?, attributes _: [String: String] = [:]) {
        let name = qName ?? elementName
        let element = Element(name: name)

        if let parent = stack.last {
            parent.addChild(element)
        } else {
            root = element
        }

        stack.append(element)
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        stack.last?.appendText(string)
    }

    func parser(_: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
        _ = stack.popLast()
    }
}
