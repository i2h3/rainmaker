// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Main command of this application.
///
@main
struct Rainmaker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [Capabilities.self, CreateDirectory.self, Delete.self, Download.self, Info.self, List.self, Login.self, Navigation.self, Poll.self, Upload.self])
}
