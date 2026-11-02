// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `POST /ocs/v2.php/apps/spreed/api/v1/chat/{token}/attachment/folder`.
///
/// This is a data transfer object covering the OCS envelope and the draft folder ``Server/sendFile(_:toConversation:caption:)`` uploads a file into before it posts the file to the conversation.
/// The server also predicts the names the files it was asked about would end up with, which is deliberately not decoded, because nothing asks it about any.
///
struct AttachmentFolderResponse: Decodable {
    ///
    /// The OCS envelope wrapping the draft folder.
    ///
    struct OCS: Decodable {
        ///
        /// The part of the answer ``Server/sendFile(_:toConversation:caption:)`` needs.
        ///
        struct Data: Decodable {
            ///
            /// The path of the draft folder relative to the account's files, without a leading slash, e.g. `"Talk/Rainmaker-abcd1234/Draft"`.
            ///
            let folder: String
        }

        ///
        /// The draft folder.
        ///
        let data: Data
    }

    ///
    /// The OCS envelope.
    ///
    let ocs: OCS
}
