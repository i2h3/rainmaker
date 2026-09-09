// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation

extension Data {
    ///
    /// The SHA-256 digest of this data as a lowercase hexadecimal string of 64 characters.
    ///
    /// ``Server`` derives the name of the folder a chunked upload is staged in from this, so that the same file uploaded to the same place is always staged in the same folder.
    /// It lives here rather than inline so that the derivation cannot drift between the places which need it, and it is deliberately not the general purpose hashing `Hasher` offers, whose results change from one process to the next.
    ///
    var sha256HexString: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
