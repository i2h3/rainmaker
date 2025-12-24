// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Arguments, options and flags shared across commands about how to format output.
///
struct FormatArguments: ParsableArguments {
    @Option(help: "In what form to render the output.")
    var outputFormat: OutputFormat = .plain
}
