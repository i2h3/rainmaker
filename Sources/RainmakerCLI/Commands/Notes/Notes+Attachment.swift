// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser

extension Notes {
    ///
    /// Attachment command grouping the retrieval, the addition and the deletion of the files attached to a note.
    ///
    /// This is a group of its own within ``Notes`` because every subcommand addresses a note and a path relative to the folder of its category, which is what `Server.addAttachment(_:toNote:fileName:)` returns and the other two take. Each subcommand is declared in a file of its own as an extension of this type, such as ``Notes/Attachment/Get`` in `Notes+Attachment+Get.swift`.
    ///
    struct Attachment: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Retrieve, add and delete the files attached to a note of the authenticated user.",
            subcommands: [Get.self, Add.self, Delete.self]
        )
    }
}
