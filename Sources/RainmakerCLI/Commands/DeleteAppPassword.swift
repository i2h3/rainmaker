// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// App password deletion command.
///
struct DeleteAppPassword: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete the app password currently used to authenticate, ending the session on the server side.")

    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        try await server.deleteAppPassword()
    }
}
