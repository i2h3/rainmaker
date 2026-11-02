// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `POST /ocs/v2.php/apps/spreed/api/v4/room`.
///
/// This is a data transfer object covering the OCS envelope around a single conversation, which ``Server/createConversation(with:)`` returns. It is the counterpart of ``ConversationsResponse``, which wraps the list of conversations in the same envelope, and decodes the conversation directly into the public ``Conversation``.
///
struct ConversationResponse: Decodable {
    ///
    /// The OCS envelope wrapping the status of the request and the conversation.
    ///
    struct OCS: Decodable {
        ///
        /// The status of the OCS request, which ``Server/createConversation(with:)`` checks before it reads ``OCS/data``.
        ///
        struct Meta: Decodable {
            ///
            /// The textual status, which is `"ok"` for a successful request.
            ///
            let status: String

            ///
            /// The numeric OCS status code, which is reported in the error when ``status`` is not `"ok"`.
            ///
            let statuscode: Int

            ///
            /// The optional message explaining a failure, which is reported in the error when ``status`` is not `"ok"`.
            ///
            let message: String?
        }

        ///
        /// The status of the request.
        ///
        let meta: Meta

        ///
        /// The conversation which was created or which already existed.
        ///
        let data: Conversation
    }

    ///
    /// The OCS envelope.
    ///
    let ocs: OCS
}
