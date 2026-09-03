// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension URL {
    ///
    /// A hidden location next to this one at which a downloaded payload is staged before it is put in place.
    ///
    /// ``Server`` downloads into the session's temporary directory, which is not necessarily on the same volume as the destination.
    /// Moving across volumes degrades into a copy followed by a delete and can fail halfway, so the payload is first moved next to its destination and only then put in place, which keeps that step within one volume.
    ///
    /// The returned name has a fixed length and deliberately does not embed the name of the destination.
    /// A remote file may legitimately use the entire length a single path component is allowed to have, commonly 255 bytes, in which case any prefixed or suffixed name would exceed that limit and the download would fail with `ENAMETOOLONG`.
    ///
    /// Every call returns a different location so that concurrent downloads into the same directory cannot stage onto each other.
    ///
    func downloadStagingLocation() -> URL {
        deletingLastPathComponent()
            .appendingCompatibility(component: ".rainmaker-\(UUID().uuidString).download", directoryHint: .notDirectory)
    }
}
