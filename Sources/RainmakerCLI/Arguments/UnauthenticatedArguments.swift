// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Arguments, options and flags shared across commands which do not require user credentials.
///
struct UnauthenticatedArguments: ParsableArguments {
    @Option(name: .shortAndLong, help: "The Nextcloud instance to connect to. Can also be set via RAINMAKER_HOST environment variable.")
    var host: String?

    mutating func validate() throws {
        try setCredentialFromEnvironment(keyPath: \.host, envVar: "RAINMAKER_HOST", optionName: "--host")
    }

    /// Helper method to set a credential from environment variable if not provided via option
    private mutating func setCredentialFromEnvironment(keyPath: WritableKeyPath<UnauthenticatedArguments, String?>, envVar: String, optionName: String) throws {
        if self[keyPath: keyPath] == nil {
            guard let envValue = ProcessInfo.processInfo.environment[envVar] else {
                throw ValidationError("Missing required option '\(optionName)' or environment variable '\(envVar)'")
            }

            self[keyPath: keyPath] = envValue
        }
    }

    /// Get the host value, guaranteed to be non-nil after validation
    var hostValue: String {
        precondition(host != nil, "hostValue accessed before validation")

        return host!
    }
}
