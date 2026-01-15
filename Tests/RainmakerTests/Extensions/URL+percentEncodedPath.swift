// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension URL {
    ///
    /// A convenience method to encode the path of a URL with a custom set of allowed characters to ensure maximum file system compatibility for test fixture paths.
    ///
    var percentEncodedPath: String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: ".")
        allowedCharacters.insert(charactersIn: "-")
        allowedCharacters.insert(charactersIn: "_")
        allowedCharacters.insert(charactersIn: "/")

        return path(percentEncoded: false).addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? path(percentEncoded: false)
    }
}
