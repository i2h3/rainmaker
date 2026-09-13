// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The avatar of a single Nextcloud user as the server resolved it.
///
/// This is what ``Server/userAvatar(_:size:darkTheme:)`` returns. The endpoint always answers with an image for a user it knows, so this is either the picture that user uploaded or one the server drew from their initials — ``isCustom`` is the only thing that tells the two apart, and it is why this type exists rather than the call returning bare bytes.
///
/// That distinction is not cosmetic. A client with a monogram style of its own has to know whether the server already drew one, or it will show the server's placeholder where it meant to show its own, and no amount of inspecting the bytes would reveal which it received.
///
public struct UserAvatar: Model {
    ///
    /// The bytes of the image exactly as the server sent them.
    ///
    public let data: Data

    ///
    /// The MIME type of ``data``, e.g. `"image/png"` or `"image/jpeg"`.
    ///
    /// This is the response's `Content-Type` and the only description of what the bytes are, which is why ``Server/userAvatar(_:size:darkTheme:)`` treats its absence as a failure rather than guessing. Unlike ``ConversationAvatar/contentType`` it is rarely an SVG document, a user avatar being a stored or rendered bitmap, but nothing about the endpoint guarantees that.
    ///
    public let contentType: String

    ///
    /// Whether the user uploaded this picture themselves, as opposed to the server having generated it from their initials.
    ///
    /// Taken from the response's `X-NC-IsCustomAvatar` header. A response that omits it is reported as `false`, which is the conservative direction: a client that draws its own monogram for a generated avatar then draws it, rather than presenting the server's placeholder as though it were somebody's photograph.
    ///
    public let isCustom: Bool
}
