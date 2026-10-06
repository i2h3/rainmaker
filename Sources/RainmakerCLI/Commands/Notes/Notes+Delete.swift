// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

extension Notes {
    ///
    /// Note deletion subcommand, which calls `Server.deleteNote(_:)`.
    ///
    /// Like the top-level `delete` command it prints nothing on success.
    ///
    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a note of the authenticated user.")

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
        /// The identifier of the note to delete.
        ///
        @Argument(help: "The identifier of the note to delete.")
        var id: Int

        func run() async throws {
            let server = try Notes.makeServer(authenticatedArguments: authenticatedArguments, unauthenticatedArguments: unauthenticatedArguments)
            try await server.deleteNote(id)
        }
    }
}
