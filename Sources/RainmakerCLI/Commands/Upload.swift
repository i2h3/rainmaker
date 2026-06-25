// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Local content upload command.
///
/// This is the counterpart of ``Download``.
///
struct Upload: AsyncParsableCommand {
    ///
    /// The configuration which describes this command to the argument parser.
    ///
    static let configuration = CommandConfiguration(abstract: "Upload a file or directory to a folder on the server.")

    ///
    /// The credentials shared across commands which require authentication.
    ///
    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    ///
    /// The connection arguments shared across commands which do not require authentication.
    ///
    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    ///
    /// The local file or directory to upload.
    ///
    @Option(help: "Local file or directory to upload.")
    var source: String

    ///
    /// The remote directory to upload the source into.
    ///
    @Option(help: "Remote folder to upload into.")
    var destination: String = "/"

    ///
    /// Whether existing remote files should be overwritten with the local state.
    ///
    @Flag(help: "Whether to overwrite existing remote files with the local state.")
    var force: Bool = false

    ///
    /// Runs the command.
    ///
    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        // `URL(filePath:)` does not expand `~`; do it ourselves so paths like `~/Documents/Notes.md`
        // resolve to the user's home directory instead of a literal `~` folder.
        let expandedSource = (source as NSString).expandingTildeInPath
        let sourceURL = URL(filePath: expandedSource, directoryHint: .inferFromPath)

        try await server.upload(sourceURL, to: destination, force: force)
    }
}
