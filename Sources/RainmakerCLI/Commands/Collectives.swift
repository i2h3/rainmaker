// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Collectives command grouping the collective listing and the page listing of a single collective.
///
struct Collectives: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the collectives of the authenticated user and their pages. Requires authentication and the server's collectives app.",
        subcommands: [List.self, Pages.self],
        defaultSubcommand: List.self
    )

    ///
    /// Collective listing subcommand.
    ///
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the collectives the authenticated user is a member of.")

        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        @OptionGroup
        var formatArguments: FormatArguments

        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
            let collectives = try await server.collectives()

            switch formatArguments.outputFormat {
                case .json:
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                    let data = try encoder.encode(collectives)

                    guard let json = String(data: data, encoding: .utf8) else {
                        throw RainmakerCommandError.encodingError
                    }

                    print(json)
                case .plain:
                    for collective in collectives {
                        // The identifier is required to list the pages of a collective, so surface it next to the name.
                        print("\(collective.id)\t\(collective.name)")
                    }
            }
        }
    }

    ///
    /// Page listing subcommand of a single collective.
    ///
    struct Pages: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the pages within a collective.")

        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        @OptionGroup
        var formatArguments: FormatArguments

        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        @Option(help: "The id of the collective to list the pages of, as shown by `collectives list`.")
        var collective: Int

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
            let pages = try await server.pages(inCollective: collective)

            switch formatArguments.outputFormat {
                case .json:
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                    let data = try encoder.encode(pages)

                    guard let json = String(data: data, encoding: .utf8) else {
                        throw RainmakerCommandError.encodingError
                    }

                    print(json)
                case .plain:
                    for page in pages {
                        print("\(page.id)\t\(page.title)")
                    }
            }
        }
    }
}
