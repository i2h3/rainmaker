// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Arguments, options and flags shared across commands.
///
struct SharedArguments: ParsableArguments {
    @Argument(help: "The Nextcloud instance to connect to.")
    var address: String

    @Argument(help: "The user account name to authenticate with.")
    var user: String

    @Option(help: "In what form to render the output.")
    var outputFormat: OutputFormat = .plain

    @Argument(help: "The password to authenticate with.")
    var password: String
}
