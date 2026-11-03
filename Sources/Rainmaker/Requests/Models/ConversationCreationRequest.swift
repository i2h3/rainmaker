// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The JSON body ``Server/createConversation(with:)`` sends to `POST /ocs/v2.php/apps/spreed/api/v4/room`.
///
/// This is a data transfer object shaped as the Talk app expects it, which is why its properties carry the server's names. It is the request counterpart of ``ConversationResponse`` and is not exposed outside this module.
///
struct ConversationCreationRequest: Encodable {
    ///
    /// The kind of conversation to create as the number the server uses for it, which is always `1`, the number the server uses for a ``ConversationType/oneToOne`` conversation.
    ///
    let roomType: Int

    ///
    /// The identifier of the other user of the one-to-one conversation.
    ///
    let invite: String
}
