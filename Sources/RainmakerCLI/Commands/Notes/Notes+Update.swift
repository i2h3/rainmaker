// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes {
    ///
    /// Note change subcommand, which calls `Server.updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`.
    ///
    /// Only the options given are sent, so everything else of the note stays as it is. It prints the note as the server stored it as ``Notes/printSummary(of:as:)`` describes, including the new entity tag to base the next change on.
    ///
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a note of the authenticated user and print its identifier, entity tag and title.")

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
        /// The identifier of the note to change.
        ///
        @Argument(help: "The identifier of the note to change.")
        var id: Int

        ///
        /// The new title, which the server sanitizes.
        ///
        @Option(help: "The new title, which renames the note's file. The note keeps its identifier.")
        var title: String?

        ///
        /// The new category.
        ///
        @Option(help: "The new category, with '/' delimiting sub-categories and an empty string for none.")
        var category: String?

        ///
        /// The new text given inline.
        ///
        @Option(help: "The new text of the note.")
        var content: String?

        ///
        /// The path of a local file holding the new text.
        ///
        @Option(help: "A local file holding the new text of the note, as an alternative to --content.")
        var contentFile: String?

        ///
        /// The moment to stamp the note with, in whole seconds since the Unix epoch.
        ///
        @Option(help: "The modification moment to stamp the note with, given as whole seconds since the Unix epoch.")
        var modified: Int?

        ///
        /// Whether the note is to be marked as a favorite.
        ///
        @Option(help: "Whether the note is marked as a favorite, 'true' or 'false'.")
        var favorite: Bool?

        ///
        /// The entity tag of the copy the change is based on, which makes the change conditional.
        ///
        @Option(help: "Change the note only while it still carries this entity tag. Otherwise nothing is changed and the command fails.")
        var ifMatch: String?

        func validate() throws {
            if content != nil, contentFile != nil {
                throw ValidationError("--content and --content-file cannot be combined.")
            }
        }

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)
            let text = try Notes.content(content, orContentsOf: contentFile)
            let modification = modified.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let note = try await server.updateNote(id, title: title, category: category, content: text, modification: modification, isFavorite: favorite, ifMatching: ifMatch)

            try Notes.printSummary(of: note, as: formatArguments.outputFormat)
        }
    }
}
