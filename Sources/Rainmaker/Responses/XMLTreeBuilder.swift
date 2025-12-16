// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// Builds an in-memory element tree from XML data using Foundation's XMLParser.
final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var root: Element?
    private var stack: [Element] = []

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() throws -> Element {
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "Failed to parse XML."
            throw RainmakerError.responseDecodingFailed(reason)
        }

        guard let root else {
            throw RainmakerError.responseDecodingFailed("Failed to get root element of document.")
        }

        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = qName ?? elementName
        let element = Element(name: name)

        if let parent = stack.last {
            parent.addChild(element)
        } else {
            root = element
        }

        stack.append(element)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.appendText(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}
