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
    /// `--summaries` leaves out the text of every note by going through the `Server.noteSummaries` counterpart of each of those calls instead, which always lists changes since a moment, so without `--changed-since` it lists every note as changed since the Unix epoch.
    /// The plain output of a listing of changes ends with `#cursor`, `#etag` and `#last-modified` lines, so that the values `--cursor`, `--if-none-match` and `--changed-since` take are at hand without the JSON output.
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
        @Option(help: "List only the notes changed at or after this moment, given as whole seconds since the Unix epoch, such as the '#last-modified' line of a previous listing. Notes which did not change are reported by their identifier alone. Defaults to the Unix epoch when another option needs a moment.")
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
        @Option(help: "Print 'Not modified.' instead of a listing when the server's answer would carry this entity tag of a previous listing, as its '#etag' line printed it.")
        var ifNoneMatch: String?

        ///
        /// Whether to list the notes without their text, through the `Server.noteSummaries` calls rather than the `Server.notes` calls.
        ///
        @Flag(help: "Leave out the text of every note, so that it is not downloaded. The listing is then always one of changes since a moment, which defaults to the Unix epoch, and its entity tag only matches later listings with this flag.")
        var summaries = false

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

            guard changedSince != nil || chunkSize != nil || ifNoneMatch != nil || summaries else {
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

            guard summaries == false else {
                try await listSummaries(on: server, changedSince: moment)
                return
            }

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
                printNotModified()
                return
            }

            switch formatArguments.outputFormat {
                case .json:
                    try print(Notes.encoded(changes))
                case .plain:
                    printPlain(titles: changes.changed.map(\.title), unchanged: changes.unchanged, chunkCursor: changes.chunkCursor, entityTag: changes.entityTag, lastModified: changes.lastModified)
            }
        }

        ///
        /// List the summaries of the notes changed since a moment, which is what `--summaries` does in place of the rest of ``run()``.
        ///
        /// It chooses among the `Server.noteSummaries` calls by the same options and prints their result in the same forms as ``run()`` prints the result of the corresponding `Server.notes` call.
        ///
        /// - Parameters:
        ///     - server: The server to list the summaries on.
        ///     - moment: The moment to list changes since.
        ///
        private func listSummaries(on server: Server, changedSince moment: Date) async throws {
            let changes: NoteSummaryChanges? = switch (chunkSize, ifNoneMatch) {
                case let (chunkSize?, ifNoneMatch?):
                    try await server.noteSummaries(changedSince: moment, chunkSize: chunkSize, ifChangedFrom: ifNoneMatch)
                case let (chunkSize?, nil):
                    try await server.noteSummaries(changedSince: moment, chunkSize: chunkSize, continuingAfter: cursor)
                case let (nil, ifNoneMatch?):
                    try await server.noteSummaries(changedSince: moment, ifChangedFrom: ifNoneMatch)
                case (nil, nil):
                    try await server.noteSummaries(changedSince: moment)
            }

            guard let changes else {
                printNotModified()
                return
            }

            switch formatArguments.outputFormat {
                case .json:
                    try print(Notes.encoded(changes))
                case .plain:
                    printPlain(titles: changes.changed.map(\.title), unchanged: changes.unchanged, chunkCursor: changes.chunkCursor, entityTag: changes.entityTag, lastModified: changes.lastModified)
            }
        }

        ///
        /// Print that the server answered a conditional listing with not modified, in the form ``formatArguments`` asks for.
        ///
        private func printNotModified() {
            switch formatArguments.outputFormat {
                case .json:
                    print("null")
                case .plain:
                    print("Not modified.")
            }
        }

        ///
        /// Print a listing of changes in the plain form, which is the same for notes with and without their text.
        ///
        /// - Parameters:
        ///     - titles: The titles of the notes sent in full, one per line.
        ///     - unchanged: The identifiers of the notes sent as identifiers alone, one per line.
        ///     - chunkCursor: The cursor to continue a chunked listing with, printed as a `#cursor` line when there is one.
        ///     - entityTag: The entity tag of the response, printed as an `#etag` line when there is one, which is what `--if-none-match` takes.
        ///     - lastModified: The moment the server says to continue from, printed as a `#last-modified` line in whole seconds since the Unix epoch when there is one, which is what `--changed-since` takes.
        ///
        private func printPlain(titles: [String], unchanged: [Int], chunkCursor: String?, entityTag: String?, lastModified: Date?) {
            for title in titles {
                print(title)
            }

            for id in unchanged {
                print("#\(id) (unchanged)")
            }

            // The cursor is what continues the pass, so it is surfaced whenever there is more to come.
            if let chunkCursor {
                print("#cursor \(chunkCursor)")
            }

            // Both values are what the next listing is based on, which the plain output would otherwise only offer through the JSON output.
            if let entityTag {
                print("#etag \(entityTag)")
            }

            if let lastModified {
                print("#last-modified \(Int(lastModified.timeIntervalSince1970.rounded(.down)))")
            }
        }
    }
}
