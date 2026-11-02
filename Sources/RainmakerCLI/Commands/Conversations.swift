// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Talk command grouping the conversation listing, the image retrieval of a single conversation, starting a one-to-one conversation and sending a message or a file into a conversation.
///
/// This is a group rather than several top-level commands because all of them use the same app through the same credentials, mirroring how ``Collectives`` groups its listing and its pages. The identifier `conversations create` takes is the one `search-users` prints, and the token `conversations send` and `conversations send-file` take is the one `conversations list` and `conversations create` print. It is named after the library methods it calls rather than after the app providing them, matching every other subcommand, and calling it `talk` would additionally shadow the library's `Talk` capability inside this module.
///
struct Conversations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the Talk conversations of the authenticated user, retrieve their images, start one-to-one conversations and send messages and files into them. Requires authentication and the server's Talk app.",
        subcommands: [List.self, Avatar.self, Create.self, Send.self, SendFile.self],
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

    ///
    /// One-to-one conversation subcommand, which calls `Server.createConversation(with:)`.
    ///
    /// The server keeps a single one-to-one conversation per pair of users, so this prints the existing conversation when there already is one. The output matches that of ``List`` for a single conversation, so that a script can cut the token to pass on to ``Send`` or ``SendFile``.
    ///
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start a one-to-one Talk conversation with a user, or find the existing one, and print it. Requires the server's Talk app.")

        ///
        /// The credentials of the account starting the conversation.
        ///
        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        ///
        /// Whether to print the conversation as plain text or as JSON.
        ///
        @OptionGroup
        var formatArguments: FormatArguments

        ///
        /// The address of the server.
        ///
        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        ///
        /// The identifier of the other user, which is neither necessarily their display name nor the name they log in with.
        ///
        /// It is not called `user` because ``AuthenticatedArguments`` already takes `--user` for the account to authenticate with.
        ///
        @Option(help: "The identifier of the user to start the conversation with, as shown by `search-users`.")
        var userId: String

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
            let conversation = try await server.createConversation(with: userId)

            switch formatArguments.outputFormat {
                case .json:
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                    let data = try encoder.encode(conversation)

                    guard let json = String(data: data, encoding: .utf8) else {
                        throw RainmakerCommandError.encodingError
                    }

                    print(json)
                case .plain:
                    print("\(conversation.token)\t\(conversation.displayName)")
            }
        }
    }

    ///
    /// Chat message subcommand, which calls `Server.sendMessage(_:toConversation:)`.
    ///
    /// Like the top-level `delete` command it prints nothing on success.
    ///
    struct Send: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Send a chat message into a Talk conversation. Requires the server's Talk app.")

        ///
        /// The credentials of the account sending the message.
        ///
        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        ///
        /// The address of the server.
        ///
        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        ///
        /// The token of the conversation to send the message into.
        ///
        @Option(help: "The token of the conversation to send to, as shown by `conversations list` or `conversations create`.")
        var token: String

        ///
        /// The text to send, which the server renders as Markdown.
        ///
        @Option(help: "The text to send.")
        var message: String

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
            try await server.sendMessage(message, toConversation: token)
        }
    }

    ///
    /// File sending subcommand, which calls `Server.sendFile(_:toConversation:caption:)`.
    ///
    /// Like ``Send`` it prints nothing on success. The file is uploaded into the account's files first, so it counts towards the account's quota.
    ///
    struct SendFile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Send a local file into a Talk conversation, optionally with a caption. Requires Talk 24 or later on the server.")

        ///
        /// The credentials of the account sending the file.
        ///
        @OptionGroup
        var authenticatedArguments: AuthenticatedArguments

        ///
        /// The address of the server.
        ///
        @OptionGroup
        var unauthenticatedArguments: UnauthenticatedArguments

        ///
        /// The token of the conversation to send the file into.
        ///
        @Option(help: "The token of the conversation to send to, as shown by `conversations list` or `conversations create`.")
        var token: String

        ///
        /// The path of the local file to send, which may start with `~`.
        ///
        @Option(help: "The local file to send. Its name becomes the name of the file on the server.")
        var file: String

        ///
        /// The text the message shows together with the file, if any.
        ///
        @Option(help: "A text to show together with the file.")
        var caption: String?

        func run() async throws {
            guard let address = URL(string: unauthenticatedArguments.hostValue) else {
                throw RainmakerCommandError.invalidAddress
            }

            let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)

            // `URL(fileURLWithPath:)` does not expand `~`; do it ourselves so paths like `~/Desktop/photo.png` resolve to the user's home directory instead of a literal `~` folder.
            let source = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
            try await server.sendFile(source, toConversation: token, caption: caption)
        }
    }
}
