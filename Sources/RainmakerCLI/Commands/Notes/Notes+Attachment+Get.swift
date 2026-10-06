// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes.Attachment {
    ///
    /// Attachment retrieval subcommand, which calls `Server.downloadAttachment(at:ofNote:to:force:)` when given a file to write to and `Server.attachment(at:ofNote:)` otherwise.
    ///
    /// Like `conversations avatar` it has no ``FormatArguments``, because the payload is a file, and the only two things worth doing with it on a command line are writing it somewhere and reporting what it is. Writing streams the file to disk rather than holding it in memory.
    ///
    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Retrieve a file attached to a note of the authenticated user.")

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
        /// The identifier of the note the path is relative to.
        ///
        @Argument(help: "The identifier of the note the path is relative to.")
        var noteId: Int

        ///
        /// The path of the file relative to the folder of the note's category, as `notes attachment add` printed it.
        ///
        @Argument(help: "The path of the file relative to the folder of the note's category, as `notes attachment add` printed it.")
        var path: String

        ///
        /// The local file to write the attachment to, if any.
        ///
        @Option(help: "Local file to write the attachment to. Without it, only the type and size of the attachment are reported.")
        var output: String?

        ///
        /// Whether an existing file at ``output`` is replaced.
        ///
        @Flag(help: "Replace the file given as --output when it exists.")
        var force: Bool = false

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)

            guard let output else {
                let attachment = try await server.attachment(at: path, ofNote: noteId)
                print("\(attachment.contentType)\t\(attachment.data.count)")
                return
            }

            // `URL(fileURLWithPath:)` does not expand `~`; do it ourselves so paths like `~/Desktop/photo.png` resolve to the user's home directory instead of a literal `~` folder.
            let expandedOutput = (output as NSString).expandingTildeInPath
            let file = try await server.downloadAttachment(at: path, ofNote: noteId, to: URL(fileURLWithPath: expandedOutput), force: force)

            print("\(file.contentType)\t\(expandedOutput)")
        }
    }
}
