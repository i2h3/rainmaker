// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Current user lookup command, which calls `Server.currentUser()`.
///
/// The plain output is the identifier and the display name separated by a tab, so that a script can cut the identifier, which can differ from the login name given with `--user`, for example to pass it on to commands addressing the account.
///
struct CurrentUser: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the identifier and the display name of the authenticated account. Requires authentication.")

    ///
    /// The credentials of the account to look up.
    ///
    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    ///
    /// Whether to print the account as plain text or as JSON.
    ///
    @OptionGroup
    var formatArguments: FormatArguments

    ///
    /// The address of the server.
    ///
    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        let user = try await server.currentUser()

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(user)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                print("\(user.id)\t\(user.displayName)")
        }
    }
}
