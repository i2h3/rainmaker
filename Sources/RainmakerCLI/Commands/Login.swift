// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

#if os(macOS)
    import AppKit
#endif

import ArgumentParser
import Foundation
import Rainmaker

///
/// Login information retrieval.
///
struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Fetch the login flow information from a server.")

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @OptionGroup
    var formatArguments: FormatArguments

    #if os(macOS)
        @Flag(help: "Open the login page in the default browser.")
        var open: Bool = false
    #endif
    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address)
        let loginFlow = try await server.login()

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let data = try encoder.encode(loginFlow)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                print("Login page: \(loginFlow.entry)")
                print("Poll address: \(loginFlow.endpoint)")
                print("Poll token: \(loginFlow.token)")
        }

        #if os(macOS)
            if open {
                NSWorkspace.shared.open(loginFlow.entry)
            }
        #endif
    }
}
