// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension URLComponents {
    ///
    /// The characters a name or a value of a query item may contain without being percent-encoded, which are those `urlQueryAllowed` permits except for `+`, `&`, `=` and `#`.
    ///
    /// `queryItems` leaves `+`, `&` and `=` as they are, because they are legal in a query, but the server reads `+` as a space and `&` and `=` as the delimiters of the items, so a value containing them reaches the server as something else, for example a file name `a+b.png` as `a b.png`. ``setEncodedQueryItems(_:)`` encodes them as well, which is what ``Server/makeAppRequest(for:method:queryItems:)`` and ``Server/makeOCSRequest(for:method:queryItems:)`` rely on.
    ///
    static let queryItemAllowedCharacters = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=#"))

    ///
    /// Set the query to the given items, percent-encoding every character of their names and values outside ``queryItemAllowedCharacters``.
    ///
    /// Unlike assigning `queryItems`, this also encodes `+`, `&`, `=` and `#`, so that every name and value reaches the server exactly as given. Items made of letters, digits and the other characters `urlQueryAllowed` permits are encoded the same way as through `queryItems`, so the query of such items does not change.
    ///
    /// - Parameters:
    ///     - items: The query items to set, in the order they should appear, with names and values which are not percent-encoded yet.
    ///
    mutating func setEncodedQueryItems(_ items: [URLQueryItem]) {
        percentEncodedQueryItems = items.map { item in
            URLQueryItem(name: Self.percentEncodedQueryComponent(item.name), value: item.value.map(Self.percentEncodedQueryComponent))
        }
    }

    ///
    /// Percent-encode a name or a value of a query item for ``setEncodedQueryItems(_:)``.
    ///
    /// Foundation only fails to encode a string which is not valid Unicode, which a Swift `String` cannot be, so the empty string it falls back to is never used in practice. It is chosen over the unencoded string because `percentEncodedQueryItems` traps on a component which is not correctly percent-encoded.
    ///
    private static func percentEncodedQueryComponent(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: queryItemAllowedCharacters) ?? ""
    }
}
