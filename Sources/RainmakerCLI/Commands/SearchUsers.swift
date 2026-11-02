// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// User search command, which calls `Server.searchUsers(_:)`.
///
/// The plain output is the identifier and the display name of each user separated by a tab, one user per line, so that a script can cut the identifier to pass on to `conversations create`.
///
struct SearchUsers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Search the users of the server by name or identifier, for example to start a Talk conversation with one. Requires authentication.")

    ///
    /// The credentials of the account searching.
    ///
    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    ///
    /// Whether to print the users as plain text or as JSON.
    ///
    @OptionGroup
    var formatArguments: FormatArguments

    ///
    /// The address of the server.
    ///
    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    ///
    /// What to search for, such as part of a display name or an identifier.
    ///
    @Option(help: "What to search for, such as part of a display name or an identifier.")
    var term: String

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        let users = try await server.searchUsers(term)

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(users)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                for user in users {
                    print("\(user.id)\t\(user.displayName)")
                }
        }
    }
}
