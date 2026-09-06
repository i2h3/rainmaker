// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Notes retrieval command.
///
struct Notes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the notes of the authenticated user. Requires authentication and the server's notes app.")

    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    @OptionGroup
    var formatArguments: FormatArguments

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @Option(help: "List only the notes modified at or after this moment, given as whole seconds since the Unix epoch. Notes which did not change are reported by their identifier alone.")
    var changedSince: Int?

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)

        guard let changedSince else {
            let notes = try await server.notes()

            switch formatArguments.outputFormat {
                case .json:
                    let json = try encoded(notes)
                    print(json)
                case .plain:
                    for note in notes {
                        print(note.title)
                    }
            }

            return
        }

        let changes = try await server.notes(changedSince: Date(timeIntervalSince1970: TimeInterval(changedSince)))

        switch formatArguments.outputFormat {
            case .json:
                let json = try encoded(changes)
                print(json)
            case .plain:
                for note in changes.changed {
                    print(note.title)
                }

                for id in changes.unchanged {
                    print("#\(id) (unchanged)")
                }
        }
    }

    ///
    /// Encode a retrieval result the way every JSON emitting subcommand does.
    ///
    private func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(value)

        guard let json = String(data: data, encoding: .utf8) else {
            throw RainmakerCommandError.encodingError
        }

        return json
    }
}
