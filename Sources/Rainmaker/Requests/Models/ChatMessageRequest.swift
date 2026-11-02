// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The JSON body ``Server/sendMessage(_:toConversation:)`` sends to `POST /ocs/v2.php/apps/spreed/api/v1/chat/{token}`.
///
/// This is a data transfer object shaped as the Talk app expects it and is not exposed outside this module.
///
struct ChatMessageRequest: Encodable {
    ///
    /// The text of the message.
    ///
    let message: String
}
