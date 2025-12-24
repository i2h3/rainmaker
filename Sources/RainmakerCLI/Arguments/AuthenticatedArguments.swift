// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

///
/// Arguments, options and flags shared across commands which require user credentials.
///
struct AuthenticatedArguments: ParsableArguments {
    @Option(name: .shortAndLong, help: "The user account name to authenticate with. Can also be set via RAINMAKER_USER environment variable.")
    var user: String?

    @Option(name: .shortAndLong, help: "The password to authenticate with. Can also be set via RAINMAKER_PASSWORD environment variable.")
    var password: String?

    mutating func validate() throws {
        try setCredentialFromEnvironment(keyPath: \.user, envVar: "RAINMAKER_USER", optionName: "--user")
        try setCredentialFromEnvironment(keyPath: \.password, envVar: "RAINMAKER_PASSWORD", optionName: "--password")
    }

    /// Helper method to set a credential from environment variable if not provided via option
    private mutating func setCredentialFromEnvironment(keyPath: WritableKeyPath<AuthenticatedArguments, String?>, envVar: String, optionName: String) throws {
        if self[keyPath: keyPath] == nil {
            guard let envValue = ProcessInfo.processInfo.environment[envVar] else {
                throw ValidationError("Missing required option '\(optionName)' or environment variable '\(envVar)'")
            }

            self[keyPath: keyPath] = envValue
        }
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
