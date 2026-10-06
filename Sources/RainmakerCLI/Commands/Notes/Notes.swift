// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Notes command grouping the listing, the retrieval, the creation, the change and the deletion of notes, as well as the ``Notes/Attachment`` group for the files attached to them.
///
/// This is a group because every subcommand reads or writes the same app through the same credentials, mirroring how ``Conversations`` groups its subcommands. Each subcommand is declared in a file of its own as an extension of this type, such as ``Notes/List`` in `Notes+List.swift`.
/// ``Notes/List`` is the default subcommand, so `notes` and `notes --changed-since <seconds>` keep listing notes as they did before this became a group.
///
/// This type shadows the library's `Notes` capability within this module, which the subcommands therefore do not refer to. Spelling that capability `Rainmaker.Notes` would not help either, because the root command of this module is called ``Rainmaker`` and shadows the library's module name in turn.
///
struct Notes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List, retrieve, create, change and delete the notes of the authenticated user and their attachments. Requires authentication and the server's notes app.",
        subcommands: [List.self, Get.self, Create.self, Update.self, Delete.self, Attachment.self],
        defaultSubcommand: List.self
    )

    ///
    /// Build the server every subcommand talks to from the arguments it was given.
    ///
    /// - Parameters:
    ///     - authenticatedArguments: The credentials, which every notes feature requires.
    ///     - unauthenticatedArguments: The address of the server.
    ///
    static func makeServer(authenticatedArguments: AuthenticatedArguments, unauthenticatedArguments: UnauthenticatedArguments) throws -> Server {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        return Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
    }

    ///
    /// Encode a result the way every JSON emitting subcommand does.
    ///
    /// - Parameters:
    ///     - value: The result to encode.
    ///
    static func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(value)

        guard let json = String(data: data, encoding: .utf8) else {
            throw RainmakerCommandError.encodingError
        }

        return json
    }

    ///
    /// Print a single note as ``Notes/Create`` and ``Notes/Update`` do.
    ///
    /// The plain form is the identifier, the entity tag and the title separated by tabs, because the identifier is what every further subcommand addresses the note by, the entity tag is what `notes update --if-match` and `notes get --if-none-match` take, and the title is what the server made of the requested one.
    ///
    /// - Parameters:
    ///     - note: The note to print.
    ///     - outputFormat: The form to print it in.
    ///
    static func printSummary(of note: Note, as outputFormat: OutputFormat) throws {
        switch outputFormat {
            case .json:
                try print(encoded(note))
            case .plain:
                print("\(note.id)\t\(note.entityTag)\t\(note.title)")
        }
    }

    ///
    /// Read the content a subcommand was given either inline or as a file.
    ///
    /// - Parameters:
    ///     - content: The content given inline, if any.
    ///     - contentFile: The path of a local file holding the content, if any, which may start with `~`.
    ///
    /// - Returns: The content, or `nil` when neither was given.
    ///
    static func content(_ content: String?, orContentsOf contentFile: String?) throws -> String? {
        guard let contentFile else {
            return content
        }

        // `URL(fileURLWithPath:)` does not expand `~`; do it ourselves so paths like `~/Documents/Note.md` resolve to the user's home directory instead of a literal `~` folder.
        let expandedPath = (contentFile as NSString).expandingTildeInPath

        return try String(contentsOf: URL(fileURLWithPath: expandedPath), encoding: .utf8)
    }
}
