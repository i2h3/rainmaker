// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Notes app settings command, which looks the settings up through `Server.notesSettings()` or, when any setting is given, changes them through `Server.updateNotesSettings(notesPath:fileSuffix:noteMode:showsHiddenFiles:loadsRecentNoteOnStartUp:)`.
///
/// Either way it prints the settings as the server has them afterwards, which after a change includes the values the server sanitized. This type shadows the library's settings model of the same name within this module, which is why the settings are only ever referred to through type inference here.
///
struct NotesSettings: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show or change where and how the notes app stores the notes of the authenticated user. Requires authentication and the server's notes app.")

    ///
    /// The credentials, which every notes feature requires.
    ///
    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    ///
    /// The form to print the settings in.
    ///
    @OptionGroup
    var formatArguments: FormatArguments

    ///
    /// The address of the server.
    ///
    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    ///
    /// The new path of the folder the notes are stored in.
    ///
    @Option(help: "Store the notes in this folder, relative to the account's files, with an empty string for the root folder. Existing notes are not moved.")
    var notesPath: String?

    ///
    /// The new file extension for notes created from now on.
    ///
    @Option(help: "Give the notes created from now on this file extension, such as '.md' or '.txt'.")
    var fileSuffix: String?

    ///
    /// The new way the web interface presents a note.
    ///
    @Option(help: "Open notes in the web interface in this mode.")
    var noteMode: NoteMode?

    ///
    /// Whether the notes app is to list hidden files and folders.
    ///
    @Option(help: "Whether files and folders whose names start with a dot are listed as notes and categories, 'true' or 'false'. Requires notes app 6.1.0 or newer.")
    var showHiddenFiles: Bool?

    ///
    /// Whether the web interface is to open the most recent note when it starts.
    ///
    @Option(help: "Whether the web interface opens the most recently edited note when it starts, 'true' or 'false'. Requires notes app 6.1.0 or newer.")
    var loadRecentNoteOnStartUp: Bool?

    ///
    /// Whether any setting to change was given, which is what makes this command change the settings rather than only show them.
    ///
    var changesSettings: Bool {
        notesPath != nil || fileSuffix != nil || noteMode != nil || showHiddenFiles != nil || loadRecentNoteOnStartUp != nil
    }

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)

        let settings = if changesSettings {
            try await server.updateNotesSettings(notesPath: notesPath, fileSuffix: fileSuffix, noteMode: noteMode, showsHiddenFiles: showHiddenFiles, loadsRecentNoteOnStartUp: loadRecentNoteOnStartUp)
        } else {
            try await server.notesSettings()
        }

        switch formatArguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(settings)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                print(settings.notesPath)
        }
    }
}
