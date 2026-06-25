// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Remote directory creation command.
///
struct CreateDirectory: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a directory on the server.")

    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @Option(help: "Remote path of the directory to create.")
    var path: String

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        try await server.createDirectory(path)
    }
}
