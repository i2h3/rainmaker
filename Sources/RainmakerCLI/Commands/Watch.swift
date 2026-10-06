// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import Rainmaker

///
/// Observe server-side changes and print each event as it arrives.
///
/// This exercises ``Rainmaker/Server/events(_:)``: it prefers the `notify_push` WebSocket when the server offers it and otherwise polls, printing one line per ``Rainmaker/ServerEvent``. It runs until interrupted.
/// The `--transport` option sets ``Rainmaker/ServerEventOptions/transport``, so `--transport polling` only polls and never opens a WebSocket.
///
struct Watch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Observe server-side changes over notify_push (or polling when unavailable or asked to) and print each event. Runs until interrupted.")

    @OptionGroup
    var authenticatedArguments: AuthenticatedArguments

    @OptionGroup
    var unauthenticatedArguments: UnauthenticatedArguments

    @Option(help: "The polling interval in seconds used when notify_push is unavailable or not used.")
    var pollInterval: Double = 30

    @Option(help: "How to learn about changes: 'automatic' prefers notify_push and polls when it is unavailable, 'polling' only polls.")
    var transport: ServerEventTransport = .automatic

    @Flag(name: .customLong("listen-file-ids"), help: "Request per-file identifiers via notify_file_id.")
    var listenFileIDs = false

    func run() async throws {
        guard let address = URL(string: unauthenticatedArguments.hostValue) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: authenticatedArguments.passwordValue, user: authenticatedArguments.userValue)
        let options = ServerEventOptions(pollInterval: pollInterval, listenFileIDs: listenFileIDs, transport: transport)

        for try await event in server.events(options) {
            print(Self.describe(event))
        }
    }

    ///
    /// Render an event as a single human-readable line.
    ///
    private static func describe(_ event: ServerEvent) -> String {
        switch event {
            case .connected:
                "connected"
            case .notifications:
                "notifications"
            case let .files(ids):
                ids.map { "files \($0)" } ?? "files"
            case .activities:
                "activities"
            case let .custom(type, body):
                body.map { "custom \(type) \($0)" } ?? "custom \(type)"
        }
    }
}
