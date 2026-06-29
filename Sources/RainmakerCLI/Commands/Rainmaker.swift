// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Main command of this application.
///
@main
struct Rainmaker: AsyncParsableCommand {
    static let configuration: CommandConfiguration = {
        var subcommands: [any ParsableCommand.Type] = [Capabilities.self, CreateDirectory.self, Delete.self, Download.self, Info.self, List.self, Login.self, Move.self, Navigation.self, Poll.self, Trash.self, Upload.self]

        // The fixture recorder controls Docker and is therefore available on macOS only.
        #if os(macOS)
            subcommands.append(RecordFixtures.self)
        #endif

        return CommandConfiguration(subcommands: subcommands)
    }()
}
