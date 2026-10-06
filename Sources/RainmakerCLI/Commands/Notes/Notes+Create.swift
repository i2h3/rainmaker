// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes {
    ///
    /// Note creation subcommand, which calls `Server.createNote(title:category:content:modification:isFavorite:)`.
    ///
    /// It prints the note the server created as ``Notes/printSummary(of:as:)`` describes, because the server assigns the identifier and may change the requested title.
    ///
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a note for the authenticated user and print its identifier, entity tag and title.")

        ///
        /// The credentials, which every notes feature requires.
        ///
        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        ///
        /// The form to print the result in.
        ///
        @OptionGroup
        var formatArguments: FormatArguments

        ///
        /// The address of the server.
        ///
        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        ///
        /// The requested title, which the server sanitizes.
        ///
        @Option(help: "The title of the new note. The server removes characters which cannot be part of a file name and numbers a title already taken.")
        var title: String

        ///
        /// The category to file the note under.
        ///
        @Option(help: "The category to file the new note under, with '/' delimiting sub-categories.")
        var category: String = ""

        ///
        /// The text of the new note given inline.
        ///
        @Option(help: "The text of the new note.")
        var content: String?

        ///
        /// The path of a local file holding the text of the new note.
        ///
        @Option(help: "A local file holding the text of the new note, as an alternative to --content.")
        var contentFile: String?

        ///
        /// The moment to stamp the new note with, in whole seconds since the Unix epoch.
        ///
        @Option(help: "The modification moment of the new note, given as whole seconds since the Unix epoch. Defaults to the moment the server writes it.")
        var modified: Int?

        ///
        /// Whether the new note is marked as a favorite.
        ///
        @Flag(help: "Mark the new note as a favorite.")
        var favorite: Bool = false

        func validate() throws {
            if content != nil, contentFile != nil {
                throw ValidationError("--content and --content-file cannot be combined.")
            }
        }

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)
            let text = try Notes.content(content, orContentsOf: contentFile) ?? ""
            let modification = modified.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let note = try await server.createNote(title: title, category: category, content: text, modification: modification, isFavorite: favorite)

            try Notes.printSummary(of: note, as: formatArguments.outputFormat)
        }
    }
}
