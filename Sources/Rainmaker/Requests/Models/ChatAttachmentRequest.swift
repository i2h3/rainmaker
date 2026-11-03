// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The JSON body ``Server/sendFile(_:toConversation:caption:)`` sends to `POST /ocs/v2.php/apps/spreed/api/v1/chat/{token}/attachment` once the file is uploaded into the draft folder ``AttachmentFolderResponse`` names.
///
/// This is a data transfer object shaped as the Talk app expects it, which is why its properties carry the server's names. It is not exposed outside this module.
///
/// The synthesized encoding leaves out ``talkMetaData`` when it is `nil`, which posts the file without a caption.
///
struct ChatAttachmentRequest: Encodable {
    ///
    /// The path of the uploaded file relative to the account's files, without a leading slash, which has to be inside the draft folder of the conversation.
    ///
    let filePath: String

    ///
    /// The name the file is given when the server moves it out of the draft folder, to which the server appends a number when the name is taken.
    ///
    let fileName: String

    ///
    /// A random value the server stores with the message, which it requires although nothing here looks the message up by it.
    ///
    let referenceId: String

    ///
    /// The metadata of the message as a JSON document in a string, e.g. `{"caption":"Hello"}`, because the server expects it encoded twice.
    ///
    let talkMetaData: String?
}
