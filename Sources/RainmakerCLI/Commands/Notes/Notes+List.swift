// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes {
    ///
    /// Notes listing subcommand, which is the default subcommand of ``Notes``.
    ///
    /// Without options it lists every note through `Server.notes()`. `--changed-since` lists the notes changed since a moment through `Server.notes(changedSince:)`, `--chunk-size` and `--cursor` retrieve one chunk of such a listing through `Server.notes(changedSince:chunkSize:continuingAfter:)`, and `--if-none-match` makes the listing, or the first chunk, conditional through `Server.notes(changedSince:ifChangedFrom:)` or `Server.notes(changedSince:chunkSize:ifChangedFrom:)`.
    ///
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the notes of the authenticated user, all of them, those changed since a moment, or one chunk of those.")

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
        /// The moment to list changes since, in whole seconds since the Unix epoch, which is the moment the previous listing reported as `lastModified`.
        ///
        @Option(help: "List only the notes changed at or after this moment, given as whole seconds since the Unix epoch. Notes which did not change are reported by their identifier alone. Defaults to the Unix epoch when another option needs a moment.")
        var changedSince: Int?

        ///
        /// The number of notes to send in full at most, which makes the listing chunked.
        ///
        @Option(help: "Retrieve one chunk of at most this many changed notes. A chunk which is not the last one prints a '#cursor' line to continue with.")
        var chunkSize: Int?

        ///
        /// The cursor of the previous chunk of the same pass.
        ///
        @Option(help: "Continue a chunked listing after the chunk this cursor was printed for. Requires --chunk-size and the same --changed-since.")
        var cursor: String?

        ///
        /// The entity tag of the previous listing, which makes the listing conditional.
        ///
        @Option(help: "Print 'Not modified.' instead of a listing when the server's answer would carry this entity tag of a previous listing.")
        var ifNoneMatch: String?

        func validate() throws {
            if cursor != nil, chunkSize == nil {
                throw ValidationError("--cursor requires --chunk-size.")
            }

            if cursor != nil, ifNoneMatch != nil {
                throw ValidationError("--cursor and --if-none-match cannot be combined, because only the first chunk of a pass can be conditional.")
            }
        }

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)

            guard changedSince != nil || chunkSize != nil || ifNoneMatch != nil else {
                let notes = try await server.notes()

                switch formatArguments.outputFormat {
                    case .json:
                        try print(Notes.encoded(notes))
                    case .plain:
                        for note in notes {
                            print(note.title)
                        }
                }

                return
            }

            let moment = Date(timeIntervalSince1970: TimeInterval(changedSince ?? 0))
            let changes: NoteChanges? = switch (chunkSize, ifNoneMatch) {
                case let (chunkSize?, ifNoneMatch?):
                    try await server.notes(changedSince: moment, chunkSize: chunkSize, ifChangedFrom: ifNoneMatch)
                case let (chunkSize?, nil):
                    try await server.notes(changedSince: moment, chunkSize: chunkSize, continuingAfter: cursor)
                case let (nil, ifNoneMatch?):
                    try await server.notes(changedSince: moment, ifChangedFrom: ifNoneMatch)
                case (nil, nil):
                    try await server.notes(changedSince: moment)
            }

            guard let changes else {
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
                    try print(Notes.encoded(changes))
                case .plain:
                    for note in changes.changed {
                        print(note.title)
                    }

                    for id in changes.unchanged {
                        print("#\(id) (unchanged)")
                    }

                    // The cursor is what continues the pass, so it is surfaced whenever there is more to come.
                    if changes.isComplete == false, let chunkCursor = changes.chunkCursor {
                        print("#cursor \(chunkCursor)")
                    }
            }
        }
    }
}
