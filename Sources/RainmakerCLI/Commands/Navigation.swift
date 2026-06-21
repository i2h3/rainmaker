// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Apps navigation retrieval command.
///
struct Navigation: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the apps navigation entries advertised by a server. Requires authentication.")

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
        let items = try await server.navigation()

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
                    print(item.name)
                }
        }
    }
}
