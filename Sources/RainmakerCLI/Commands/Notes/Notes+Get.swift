// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes {
    ///
    /// Single note retrieval subcommand, which calls `Server.note(_:)`, or `Server.note(_:ifChangedFrom:)` when given an entity tag.
    ///
    /// The plain output is the content of the note alone, so it can be piped elsewhere as the text it is, while the JSON output carries every other value as well.
    ///
    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Retrieve a single note of the authenticated user by its identifier.")

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
        /// The identifier of the note to retrieve.
        ///
        @Argument(help: "The identifier of the note to retrieve.")
        var id: Int

        ///
        /// The entity tag of the copy at hand, which makes the retrieval conditional.
        ///
        @Option(help: "Print 'Not modified.' instead of the note while it still carries this entity tag.")
        var ifNoneMatch: String?

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)
            let note: Note? = if let ifNoneMatch {
                try await server.note(id, ifChangedFrom: ifNoneMatch)
            } else {
                try await server.note(id)
            }

            guard let note else {
                switch formatArguments.outputFormat {
                    case .json:
                        print("null")
                    case .plain:
                        print("Not modified.")
                }

                return
            }

            switch formatArguments.outputFormat {
                case .json:
                    try print(Notes.encoded(note))
                case .plain:
                    // The content is printed as it is, without a line break the note itself does not end with.
                    print(note.content, terminator: "")
            }
        }
    }
}
