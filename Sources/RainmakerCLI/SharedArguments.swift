// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Arguments, options and flags shared across commands.
///
struct SharedArguments: ParsableArguments {
    @Option(
        name: .shortAndLong,
        help: "The Nextcloud instance to connect to. Can also be set via RAINMAKER_HOST environment variable."
    )
    var host: String?

    @Option(
        name: .shortAndLong,
        help: "The user account name to authenticate with. Can also be set via RAINMAKER_USER environment variable."
    )
    var user: String?

    @Option(help: "In what form to render the output.")
    var outputFormat: OutputFormat = .plain

    @Option(
        name: .shortAndLong,
        help: "The password to authenticate with. Can also be set via RAINMAKER_PASSWORD environment variable."
    )
    var password: String?

    mutating func validate() throws {
        try setCredentialFromEnvironment(
            keyPath: \.host,
            envVar: "RAINMAKER_HOST",
            optionName: "--host"
        )

        try setCredentialFromEnvironment(
            keyPath: \.user,
            envVar: "RAINMAKER_USER",
            optionName: "--user"
        )

        try setCredentialFromEnvironment(
            keyPath: \.password,
            envVar: "RAINMAKER_PASSWORD",
            optionName: "--password"
        )
    }

    /// Helper method to set a credential from environment variable if not provided via option
    private mutating func setCredentialFromEnvironment(
        keyPath: WritableKeyPath<SharedArguments, String?>,
        envVar: String,
        optionName: String
    ) throws {
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

    /// Get the user value, guaranteed to be non-nil after validation
    var userValue: String {
        precondition(user != nil, "userValue accessed before validation")
        return user!
    }

    /// Get the password value, guaranteed to be non-nil after validation
    var passwordValue: String {
        precondition(password != nil, "passwordValue accessed before validation")
        return password!
    }
}
