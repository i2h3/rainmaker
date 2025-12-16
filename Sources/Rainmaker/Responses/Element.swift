// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// 
/// Lightweight XML node representation used by the WebDAV response parser.
///
final class Element {
    let name: String
    private(set) var text: String = ""
    private(set) var children: [Element] = []

    init(name: String) {
        self.name = name
    }

    func appendText(_ string: String) {
        text.append(string)
    }

    func addChild(_ child: Element) {
        children.append(child)
    }

    func elements(forName name: String) -> [Element] {
        children.filter { $0.name == name }
    }

    func firstElement(forName name: String) -> Element? {
        elements(forName: name).first
    }

    var stringValue: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
