// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Activity stream retrieval command.
///
/// This exercises ``Rainmaker/Server/activities(filter:since:limit:sort:previews:objectType:objectId:)``, which returns a single page. Paging is therefore driven from the outside by passing the previously reported cursor to `--since`.
///
struct Activities: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List one page of the activity stream of the authenticated user. Requires authentication and the server's activity app.")

    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    @OptionGroup
    var formatArguments: FormatArguments

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @Option(help: "Which subset of the stream to list. Run the activity-filters subcommand to discover what a server offers.")
    var filter: String = ActivityFilter.all

    @Option(help: "The identifier of the activity to continue after, exclusively.")
    var since: Int = 0

    @Option(help: "How many activities to list at most, within 1 to 200.")
    var limit: Int = 50

    @Option(help: "The direction to walk the stream in.")
    var sort: ActivitySort = .newestFirst

    @Option(help: "The type of a single object to narrow the stream down to, e.g. files. Only effective together with --object-id.")
    var objectType: String?

    @Option(help: "The identifier of a single object to narrow the stream down to. Only effective together with --object-type.")
    var objectId: String?

    @Flag(help: "Include the thumbnails of the files the activities refer to.")
    var previews = false

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        let page = try await server.activities(filter: filter, since: since, limit: limit, sort: sort, previews: previews, objectType: objectType, objectId: objectId)

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                // The whole page is encoded rather than just its items so that the cursors needed to request the following page are part of the output.
                let data = try encoder.encode(page)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                for item in page.items {
                    print(item.subject)
                }
        }
    }
}
