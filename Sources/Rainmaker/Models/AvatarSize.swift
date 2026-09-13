// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One of the two avatar edge lengths a Nextcloud server actually serves.
///
/// The endpoint behind ``Server/userAvatar(_:size:darkTheme:)`` takes a pixel size in its path but does not honour it: it rounds anything up to 64 or down from above to 512, and logs every other value as a deprecated request. Modelling the two it keeps, rather than accepting an arbitrary integer, is what stops a caller asking for 128 and quietly receiving 512 while believing otherwise.
///
public enum AvatarSize: Int, Sendable, CaseIterable {
    ///
    /// The 64 pixel variant, which the server serves for any requested size up to and including 64.
    ///
    /// This is the one to ask for wherever an avatar is drawn small — a list row, or a widget's circle — since the larger variant only costs bytes there.
    ///
    case small = 64

    ///
    /// The 512 pixel variant, which the server serves for any requested size above 64.
    ///
    case large = 512
}
