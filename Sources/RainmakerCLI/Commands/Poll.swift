// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Login flow status polling.
///
struct Poll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Poll the status of a previously initiated login flow.")

    @OptionGroup
    var formatArguments: FormatArguments

    @Argument(help: "The address which to poll for login flow status.")
    var endpoint: String

    @Argument(help: "The token to identify the login flow.")
    var token: String

    @Option(help: "How many times the endpoint should be polled before failing.")
    var tries: Int = 300

    func run() async throws {
        guard let address = URL(string: endpoint) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address)

        var currentTry = 0
        var loginResult: LoginResult?

        while currentTry < tries {
            currentTry += 1

            if formatArguments.outputFormat == .plain {
                print("Polling (try \(currentTry) out of \(tries))...")
            }

            do {
                loginResult = try await server.poll(address, token: token)

                if formatArguments.outputFormat == .plain {
                    print("Received result.")
                }

                break
            } catch RainmakerError.responseDecodingFailed {
                // The server may respond with an empty array ("[]") while the flow is incomplete.
                // This is also expected and can be ignored to continue polling.
            }

            try await Task.sleep(for: .seconds(1))
        }

        if let loginResult {
            switch formatArguments.outputFormat {
                case .json:
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    let data = try encoder.encode(loginResult)

                    guard let json = String(data: data, encoding: .utf8) else {
                        throw RainmakerCommandError.encodingError
                    }

                    print(json)
                case .plain:
                    print("Name: \(loginResult.name)")
                    print("Password: \(loginResult.password)")
                    print("Server: \(loginResult.server)")
            }
        } else {
            throw RainmakerCommandError.maximumTriesExhausted
        }
    }
}
