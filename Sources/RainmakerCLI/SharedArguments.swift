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
        help: "The Nextcloud instance to connect to. Can also be set via RAINMAKER_ADDRESS environment variable."
    )
    var address: String?

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
        // Check if address is provided via option or environment variable
        if address == nil {
            guard let envAddress = ProcessInfo.processInfo.environment["RAINMAKER_ADDRESS"] else {
                throw ValidationError("Missing required option '--address' or environment variable 'RAINMAKER_ADDRESS'")
            }
            address = envAddress
        }
        
        // Check if user is provided via option or environment variable
        if user == nil {
            guard let envUser = ProcessInfo.processInfo.environment["RAINMAKER_USER"] else {
                throw ValidationError("Missing required option '--user' or environment variable 'RAINMAKER_USER'")
            }
            user = envUser
        }
        
        // Check if password is provided via option or environment variable
        if password == nil {
            guard let envPassword = ProcessInfo.processInfo.environment["RAINMAKER_PASSWORD"] else {
                throw ValidationError("Missing required option '--password' or environment variable 'RAINMAKER_PASSWORD'")
            }
            password = envPassword
        }
    }
    
    /// Get the address value, guaranteed to be non-nil after validation
    var addressValue: String {
        address!
    }
    
    /// Get the user value, guaranteed to be non-nil after validation
    var userValue: String {
        user!
    }
    
    /// Get the password value, guaranteed to be non-nil after validation
    var passwordValue: String {
        password!
    }
}
