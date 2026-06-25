// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Trash bin management command grouping the listing, restore and empty operations.
///
struct Trash: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage the server trash bin.",
        subcommands: [List.self, Restore.self, Empty.self],
        defaultSubcommand: List.self
    )

    ///
    /// Trash bin listing subcommand.
    ///
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the items in the trash bin.")

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
            let items: [TrashItem] = try await server.trash()

            switch formatArguments.outputFormat {
                case .json:
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                    let data = try encoder.encode(items)

                    guard let json = String(data: data, encoding: .utf8) else {
                        throw RainmakerCommandError.encodingError
                    }

                    print(json)
                case .plain:
                    for item in items {
                        // The id is required to restore an item, so surface it next to the original location.
                        print("\(item.id)\t\(item.originalLocation)")
                    }
            }
        }
    }

    ///
    /// Trash bin restore subcommand.
    ///
    struct Restore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restore an item from the trash bin to its original location.")

        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        @Option(help: "The id of the trash item to restore, as shown by `trash list`.")
        var id: String

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
            try await server.restore(id)
        }
    }

    ///
    /// Trash bin empty subcommand.
    ///
    struct Empty: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Permanently delete all items in the trash bin.")

        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
            try await server.emptyTrash()
        }
    }
}
