// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Notes app settings lookup command.
///
struct NotesSettings: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show where the notes app stores the notes of the authenticated user. Requires authentication and the server's notes app.")

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
        let settings = try await server.notesSettings()

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(settings)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                print(settings.notesPath)
        }
    }
}
