// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// User notifications retrieval command.
///
struct Notifications: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the notifications queued for the authenticated user. Requires authentication and the server's notifications app.")

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
        let items = try await server.notifications()

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(items)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                for item in items {
                    print(item.subject)
                }
        }
    }
}
