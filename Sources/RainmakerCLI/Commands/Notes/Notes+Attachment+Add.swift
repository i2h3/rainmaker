// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes.Attachment {
    ///
    /// Attachment addition subcommand, which calls `Server.addAttachment(_:toNote:fileName:)` with a local file.
    ///
    /// It prints the path the server stored the file at, which is what `notes attachment get` and `notes attachment delete` take and what the note's content can reference.
    ///
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Attach a local file to a note of the authenticated user and print the path the server stored it at.")

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
        /// The identifier of the note to attach the file to.
        ///
        @Argument(help: "The identifier of the note to attach the file to.")
        var noteId: Int

        ///
        /// The path of the local file to attach, which may start with `~`.
        ///
        @Argument(help: "The local file to attach.")
        var file: String

        ///
        /// The name to store the file under, if it differs from that of ``file``.
        ///
        @Option(help: "The name to store the file under. Defaults to the name of the local file.")
        var name: String?

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)

            // `URL(fileURLWithPath:)` does not expand `~`; do it ourselves so paths like `~/Desktop/photo.png` resolve to the user's home directory instead of a literal `~` folder.
            let source = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
            let path = try await server.addAttachment(source, toNote: noteId, fileName: name)

            print(path)
        }
    }
}
