// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes.Attachment {
    ///
    /// Attachment deletion subcommand, which calls `Server.deleteAttachment(at:ofNote:)`.
    ///
    /// Like `notes delete` it prints nothing on success. Releases of the notes app before 6.1.0 do not offer the deletion of attachments and make it fail.
    ///
    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a file attached to a note of the authenticated user. Requires the notes app 6.1.0 or newer.")

        ///
        /// The credentials, which every notes feature requires.
        ///
        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        ///
        /// The address of the server.
        ///
        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        ///
        /// The identifier of the note the attachment belongs to.
        ///
        @Argument(help: "The identifier of the note the attachment belongs to.")
        var noteId: Int

        ///
        /// The path of the attachment as `notes attachment add` printed it.
        ///
        @Argument(help: "The path of the attachment as `notes attachment add` printed it.")
        var path: String

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)
            try await server.deleteAttachment(at: path, ofNote: noteId)
        }
    }
}
