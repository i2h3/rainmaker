// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension FileManager {
    ///
    /// Throw ``RainmakerError/fileAlreadyExists(_:)`` when a directory exists at the given location, which is what ``Server/downloadAttachment(at:ofNote:to:force:)`` checks before it puts a file in place.
    ///
    /// Unlike `assertFileDoesNotExist(at:)`, this passes for a regular file, so a caller which is allowed to replace a file can still refuse a directory, which `replaceItemAt(_:withItemAt:backupItemName:options:)` would otherwise delete together with everything in it.
    ///
    /// - Parameters:
    ///     - location: The local location to check.
    ///
    func assertNotDirectory(at location: URL) throws {
        var isDirectory: ObjCBool = false

        if fileExists(atPath: location.compatibilityPath(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue {
            throw RainmakerError.fileAlreadyExists(location)
        }
    }
}
