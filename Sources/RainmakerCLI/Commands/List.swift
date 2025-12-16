// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Remote content listing command.
///
struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the content of a directory on the server by the given path.")

    @OptionGroup
    var arguments: SharedArguments

    @Option(help: "Path to list the content of as in the account.")
    var path: String = "/"

    @Option(help: "Whether content of subdirectories should also be listed.")
    var recursive: Bool = false

    func run() async throws {
        guard let address = URL(string: arguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: arguments.passwordValue, user: arguments.userValue)
        let stream = try await server.enumerate(at: path, recursively: recursive)
        var items = [Item]()

        for try await item in stream {
            items.append(item)
        }

        switch arguments.outputFormat {
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
                    print(item.path)
                }
        }
    }
}
