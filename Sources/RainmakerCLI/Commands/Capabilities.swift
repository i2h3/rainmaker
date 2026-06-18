// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Server capabilities retrieval.
///
struct Capabilities: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Fetch the capabilities advertised by a server. Authentication is optional.")

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @OptionGroup
    var formatArguments: FormatArguments

    @Option(name: .shortAndLong, help: "Optional user account name to authenticate with for the full capability set. Can also be set via RAINMAKER_USER environment variable.")
    var user: String?

    @Option(name: .shortAndLong, help: "Optional password to authenticate with. Only used together with --user. Can also be set via RAINMAKER_PASSWORD environment variable.")
    var password: String?

    mutating func validate() throws {
        if user == nil {
            user = ProcessInfo.processInfo.environment["RAINMAKER_USER"]
        }

        if password == nil {
            password = ProcessInfo.processInfo.environment["RAINMAKER_PASSWORD"]
        }
    }

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: password, user: user)
        let capabilities = try await server.capabilities()

        switch formatArguments.outputFormat {
            case .json:
                let object = try JSONSerialization.jsonObject(with: capabilities.raw)
                let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                print("Server version: \(capabilities.version.string)")
        }
    }
}
