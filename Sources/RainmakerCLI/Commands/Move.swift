// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Remote relocation (move/rename) command.
///
struct Move: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Move or rename a remote file or directory on the server.")

    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @Option(help: "Remote path of the file or directory to move.")
    var source: String

    @Option(help: "Remote target path. A different final component renames the item.")
    var destination: String

    @Flag(help: "Overwrite an existing remote item at the destination (maps to the WebDAV Overwrite header).")
    var force: Bool = false

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        try await server.move(source, to: destination, overwrite: force)
    }
}
