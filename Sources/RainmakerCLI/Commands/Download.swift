// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Remote content download command.
///
struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Download a file or directory from the server.")

    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @Option(help: "Remote path to download.")
    var source: String

    @Option(help: "Local directory to download to.")
    var destination: String = "."

    @Flag(help: "Whether to overwrite existing local files with the remote state.")
    var force: Bool = false

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        // `URL(fileURLWithPath:)` does not expand `~`; do it ourselves so paths like `~/Downloads/Rainmaker`
        // resolve to the user's home directory instead of a literal `~` folder.
        let expandedDestination = (destination as NSString).expandingTildeInPath
        let destinationURL = URL(fileURLWithPath: expandedDestination, isDirectory: true)

        try await server.download(source, to: destinationURL, force: force)
    }
}
