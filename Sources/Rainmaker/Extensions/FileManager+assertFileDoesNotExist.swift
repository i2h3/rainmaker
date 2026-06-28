// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension FileManager {
    func assertFileDoesNotExist(at location: URL) throws {
        if fileExists(atPath: location.compatibilityPath(percentEncoded: false)) {
            throw RainmakerError.fileAlreadyExists(location)
        }
    }
}
