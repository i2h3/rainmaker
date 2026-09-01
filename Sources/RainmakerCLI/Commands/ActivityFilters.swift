// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Activity filter discovery command.
///
/// The identifiers this prints are what the `--filter` option of the `activities` subcommand accepts, because a server and its apps contribute their own filters beyond the well-known ones.
///
struct ActivityFilters: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "activity-filters", abstract: "List the filters the server offers to narrow the activity stream down with. Requires authentication and the server's activity app.")

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
        let filters = try await server.activityFilters()

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(filters)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                for filter in filters {
                    print("\(filter.id)\t\(filter.name)")
                }
        }
    }
}
