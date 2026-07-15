// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
@testable import Rainmaker
import Testing

///
/// End-to-end behavior of ``Serving/events(_:)``: transport selection, frame delivery, polling fallback, reconnection, and authentication failures.
///
/// These drive the coordinator with mock transports and tiny timing so no network or live server is involved.
///
@Suite("Server Events") struct ServerEventsTests {
    // MARK: - Fixtures

    private var account: URL {
        URL(string: "https://localhost/")!
    }

    ///
    /// A capabilities envelope, optionally advertising `notify_push` for the given subjects.
    ///
    private func capabilities(pushing types: [String]?) -> String {
        var capabilities = #""notifications":{"ocs-endpoints":["list"]}"#

        if let types {
            let list = types.map { "\"\($0)\"" }.joined(separator: ",")
            capabilities += #",\#n"notify_push":{"type":[\#(list)],"endpoints":{"websocket":"wss://localhost/push/ws"}}"#
        }

        return #"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"version":{"major":31,"minor":0,"micro":0,"string":"31.0.0","edition":"","extendedSupport":false},"capabilities":{\#(capabilities)}}}}"#
    }

    ///
    /// Build a ``Server`` wired to the given mock transports.
    ///
    private func makeServer(session: any Requesting, webSocket: any WebSocketConnecting, authenticated: Bool = true) -> Server {
        Server(address: account, password: authenticated ? "admin" : nil, user: authenticated ? "admin" : nil, session: session, webSocket: webSocket, userAgent: "RainmakerTests")
    }

    ///
    /// Build the event stream through a coordinator configured with tiny retry and backoff timing so the tests run quickly.
    ///
    private func makeStream(server: Server, options: ServerEventOptions) -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            guard server.user != nil, server.password != nil else {
                continuation.finish(throwing: RainmakerError.credentialsRequired)
                return
            }

            let coordinator = ServerEventCoordinator(server: server, options: options, logger: Logger(subsystem: "RainmakerTests", category: "ServerEvents"), maximumAuthenticationAttempts: 2, authenticationRetryInterval: 0.02, rediscoverInterval: 0.3, backoffCeiling: 0.05, initialBackoff: 0.01)
            let task = Task {
                await coordinator.run(into: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    ///
    /// Collect the first `count` events, guarded by a timeout so a stalled stream fails the test instead of hanging.
    ///
    private func firstEvents(_ count: Int, from stream: AsyncThrowingStream<ServerEvent, Error>) async throws -> [ServerEvent] {
        try await withTimeout(seconds: 3) {
            var events: [ServerEvent] = []

            for try await event in stream {
                events.append(event)

                if events.count >= count {
                    break
                }
            }

            return events
        }
    }

    // MARK: - Tests

    @Test("Polls When Push Is Unavailable")
    func pollsWhenPushUnavailable() async throws {
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: nil)), webSocket: MockWebSocketConnecting(channels: []))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 0.03))

        let events = try await firstEvents(3, from: stream)
        #expect(events == [.connected, .notifications, .notifications])
    }

    @Test("Delivers Pushed Notifications")
    func deliversPushedNotifications() async throws {
        let channel = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [channel]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false))

        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .notifications])
        #expect(await channel.sentFrames() == ["admin", "admin"])
    }

    @Test("Delivers Pushed File Identifiers")
    func deliversPushedFileIdentifiers() async throws {
        let channel = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_file_id [10,20]")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["files"])), webSocket: MockWebSocketConnecting(channels: [channel]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.files], pollInterval: 100, listenFileIDs: true, emitConnectedOnStart: false))

        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .files(ids: [10, 20])])
        #expect(await channel.sentFrames() == ["admin", "admin", "listen notify_file_id"])
    }

    @Test("Reconnects And Reconciles")
    func reconnectsAndReconciles() async throws {
        let first = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")], closesWhenExhausted: true)
        let second = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [first, second]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false))

        // The first socket delivers one hint then drops; the coordinator reconnects and emits another connected reconcile signal.
        let events = try await firstEvents(4, from: stream)
        #expect(events == [.connected, .notifications, .connected, .notifications])
    }

    @Test("Falls Back To Polling After Repeated Auth Rejection")
    func fallsBackToPollingAfterAuthRejection() async throws {
        let rejecting = { MockWebSocketChannel(frames: [.text("err: Invalid credentials")], closesWhenExhausted: true) }
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [rejecting(), rejecting()]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 0.03))

        // The socket keeps rejecting authentication, so after the bounded retries the coordinator falls back to polling rather than throwing.
        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .notifications])
    }

    @Test("Ends On Unauthorized Discovery")
    func endsOnUnauthorizedDiscovery() async throws {
        let server = makeServer(session: MockRequesting(string: "unauthorized", statusCode: 401), webSocket: MockWebSocketConnecting(channels: []))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], emitConnectedOnStart: false))

        await #expect(throws: RainmakerError.unexpectedStatus(code: 401)) {
            _ = try await firstEvents(1, from: stream)
        }
    }

    @Test("Ends Without Credentials")
    func endsWithoutCredentials() async throws {
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: nil)), webSocket: MockWebSocketConnecting(channels: []), authenticated: false)

        // The public entry point finishes the stream immediately when no credentials are set.
        await #expect(throws: RainmakerError.credentialsRequired) {
            for try await _ in server.events(ServerEventOptions(subjects: [.notifications])) {
                break
            }
        }
    }
}
