// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Main command of this application.
///
@main
struct Rainmaker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [List.self, Login.self, Poll.self])
}
