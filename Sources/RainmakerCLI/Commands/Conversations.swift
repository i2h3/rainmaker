// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Talk command grouping the conversation listing and the image retrieval of a single conversation.
///
/// This is a group rather than two top-level commands because both read the same app through the same credentials, mirroring how ``Collectives`` groups its listing and its pages. It is named after the library methods it calls rather than after the app providing them, matching every other subcommand, and calling it `talk` would additionally shadow the library's `Talk` capability inside this module.
///
struct Conversations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the Talk conversations of the authenticated user and retrieve their images. Requires authentication and the server's Talk app.",
        subcommands: [List.self, Avatar.self],
        defaultSubcommand: List.self
    )

    ///
    /// Conversation listing subcommand.
    ///
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the Talk conversations the authenticated user takes part in.")

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
            let conversations = try await server.conversations()

            switch formatArguments.outputFormat {
                case .json:
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                    let data = try encoder.encode(conversations)

                    guard let json = String(data: data, encoding: .utf8) else {
                        throw RainmakerCommandError.encodingError
                    }

                    print(json)
                case .plain:
                    for conversation in conversations {
                        // The token is what every further Talk request addresses a conversation by, so surface it next to the name.
                        print("\(conversation.token)\t\(conversation.displayName)")
                    }
            }
        }
    }

    ///
    /// Image retrieval subcommand of a single conversation.
    ///
    /// This subcommand deliberately has no ``FormatArguments``: the payload is an image, and the only two things worth doing with it on a command line are writing it somewhere and reporting what it is. Rendering it as JSON would mean base64 on standard output, which serves nobody.
    ///
    struct Avatar: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Retrieve the image of a Talk conversation.")

        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        @Option(help: "The token of the conversation to retrieve the image of, as shown by `conversations list`.")
        var token: String

        @Option(help: "Local file to write the image to. Without it, only the type and size of the image are reported.")
        var output: String?

        @Flag(help: "Whether to retrieve the variant meant for a dark appearance.")
        var darkTheme: Bool = false

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
            let avatar = try await server.conversationAvatar(token, darkTheme: darkTheme)

            guard let output else {
                print("\(avatar.contentType)\t\(avatar.data.count)")
                return
            }

            // `URL(fileURLWithPath:)` does not expand `~`; do it ourselves so paths like `~/Desktop/avatar.svg` resolve to the user's home directory instead of a literal `~` folder.
            let expandedOutput = (output as NSString).expandingTildeInPath
            try avatar.data.write(to: URL(fileURLWithPath: expandedOutput))

            print("\(avatar.contentType)\t\(expandedOutput)")
        }
    }
}
