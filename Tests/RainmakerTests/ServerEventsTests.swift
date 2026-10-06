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
/// The tests which expect a WebSocket to be opened are enabled only where ``ServerEventCoordinator/platformSupportsWebSocket`` is `true`, because the automatic transport polls on watchOS, which a test of its own covers there.
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
    private func makeStream(server: Server, options: ServerEventOptions, pingInterval: TimeInterval = 30, pongTimeout: TimeInterval = 10, rediscoverInterval: TimeInterval = 0.3, maximumConnectionFailures: Int = 3) -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            guard server.user != nil, server.password != nil else {
                continuation.finish(throwing: RainmakerError.credentialsRequired)
                return
            }

            let coordinator = ServerEventCoordinator(server: server, options: options, logger: Logger(subsystem: "RainmakerTests", category: "ServerEvents"), maximumAuthenticationAttempts: 2, maximumConnectionFailures: maximumConnectionFailures, authenticationRetryInterval: 0.02, rediscoverInterval: rediscoverInterval, backoffCeiling: 0.05, initialBackoff: 0.01, pingInterval: pingInterval, pongTimeout: pongTimeout)
            let task = Task {
                await coordinator.run(into: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    ///
    /// Collect the given number of events from a stream, failing the test rather than hanging it if they never arrive.
    ///
    /// The timeout is a guard against a stalled stream, not an assertion about how quickly the coordinator works. It is therefore generous on purpose: the cadences these tests configure are in the tens of milliseconds, so any value far above that distinguishes a hang from a slow machine, and a simulator under load is slow enough to miss a tight deadline while behaving correctly.
    ///
    private func firstEvents(_ count: Int, from stream: AsyncThrowingStream<ServerEvent, Error>) async throws -> [ServerEvent] {
        try await withTimeout(seconds: 30) {
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

    @Test("Delivers Pushed Notifications", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func deliversPushedNotifications() async throws {
        let channel = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [channel]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false))

        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .notifications])
        #expect(await channel.sentFrames() == ["admin", "admin"])
    }

    @Test("Delivers Pushed File Identifiers", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func deliversPushedFileIdentifiers() async throws {
        let channel = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_file_id [10,20]")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["files"])), webSocket: MockWebSocketConnecting(channels: [channel]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.files], pollInterval: 100, listenFileIDs: true, emitConnectedOnStart: false))

        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .files(ids: [10, 20])])
        #expect(await channel.sentFrames() == ["admin", "admin", "listen notify_file_id"])
    }

    @Test("Reconnects And Reconciles", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func reconnectsAndReconciles() async throws {
        let first = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")], closesWhenExhausted: true)
        let second = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [first, second]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false))

        // The first socket delivers one hint then drops; the coordinator reconnects and emits another connected reconcile signal.
        let events = try await firstEvents(4, from: stream)
        #expect(events == [.connected, .notifications, .connected, .notifications])
    }

    @Test("Closes The Socket When The Consumer Stops", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func closesTheSocketWhenTheConsumerStops() async throws {
        let channel = MockWebSocketChannel(frames: [.text("authenticated")], ignoresTaskCancellation: true)
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [channel]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false))
        let connected = LockedValue(false)

        let consumer = Task {
            for try await event in stream where event == .connected {
                connected.set(true)
            }
        }

        try #require(try await eventually { connected.get() })

        // The channel keeps receiving through a stop like URLSession does, so only closing it ends the session.
        consumer.cancel()
        #expect(try await eventually { channel.closure.isClosed })
    }

    @Test("Closes The Socket When The Consumer Stops During Authentication", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func closesTheSocketWhenTheConsumerStopsDuringAuthentication() async throws {
        let channel = MockWebSocketChannel(frames: [], ignoresTaskCancellation: true)
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [channel]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false))

        let consumer = Task {
            for try await _ in stream {}
        }

        // The server never confirms authentication, so the session waits in its handshake when the consumer stops.
        try #require(try await eventually { await channel.sentFrames() == ["admin", "admin"] })
        consumer.cancel()
        #expect(try await eventually { channel.closure.isClosed })
    }

    @Test("Reconnects When A Pong Never Arrives", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func reconnectsWhenAPongNeverArrives() async throws {
        let silent = MockWebSocketChannel(frames: [.text("authenticated")], ignoresTaskCancellation: true, pingBehavior: .never)
        let answering = MockWebSocketChannel(frames: [.text("authenticated")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [silent, answering]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false), pingInterval: 0.02, pongTimeout: 0.05)

        // The first socket stays open but never answers a ping, so the timeout closes it and the coordinator reconnects.
        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .connected])
        #expect(silent.closure.isClosed)
    }

    @Test("Reconnects When A Pong Never Arrives Although The Ping Ignores Cancellation", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func reconnectsWhenAPongNeverArrivesAlthoughThePingIgnoresCancellation() async throws {
        let silent = MockWebSocketChannel(frames: [.text("authenticated")], ignoresTaskCancellation: true, pingBehavior: .neverIgnoringCancellation)
        let answering = MockWebSocketChannel(frames: [.text("authenticated")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [silent, answering]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false), pingInterval: 0.02, pongTimeout: 0.05)

        // Only closing the channel ends a ping like this one, so that is what the timeout has to do.
        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .connected])
        #expect(silent.closure.isClosed)
    }

    @Test("Keeps The Socket Open While Pongs Arrive", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func keepsTheSocketOpenWhilePongsArrive() async throws {
        let channel = MockWebSocketChannel(frames: [.text("authenticated")])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [channel]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false), pingInterval: 0.01, pongTimeout: 5)
        let events = LockedValue<[ServerEvent]>([])

        let consumer = Task {
            for try await event in stream {
                events.withValue { $0.append(event) }
            }
        }

        defer {
            consumer.cancel()
        }

        // The timeout is far above any scheduling delay, so only a ping answered in time being treated as lost would end the session.
        try #require(try await eventually { await channel.pingCount() >= 5 })
        #expect(channel.closure.isClosed == false)
        #expect(events.get() == [.connected])
    }

    @Test("Falls Back To Polling After Repeated Auth Rejection", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func fallsBackToPollingAfterAuthRejection() async throws {
        let rejecting = { MockWebSocketChannel(frames: [.text("err: Invalid credentials")], closesWhenExhausted: true) }
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: MockWebSocketConnecting(channels: [rejecting(), rejecting()]))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 0.03))

        // The socket keeps rejecting authentication, so after the bounded retries the coordinator falls back to polling rather than throwing.
        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .notifications])
    }

    @Test("Ends On Unauthorized Discovery", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func endsOnUnauthorizedDiscovery() async throws {
        let server = makeServer(session: MockRequesting(string: "unauthorized", statusCode: 401), webSocket: MockWebSocketConnecting(channels: []))
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], emitConnectedOnStart: false))

        await #expect(throws: RainmakerError.unexpectedStatus(code: 401)) {
            _ = try await firstEvents(1, from: stream)
        }
    }

    @Test("Falls Back To Polling After Repeated Connection Failures", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func fallsBackToPollingAfterRepeatedConnectionFailures() async throws {
        let failing = { MockWebSocketChannel(frames: [], closesWhenExhausted: true) }
        let connector = MockWebSocketConnecting(channels: [failing(), failing(), failing()])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: connector)
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 0.03), rediscoverInterval: 30)

        // Every socket drops before it authenticates, so after the third failure the coordinator polls instead of reconnecting forever, and the long window keeps it from trying the socket again while the test looks.
        let events = try await firstEvents(2, from: stream)
        #expect(events == [.connected, .notifications])
        #expect(connector.openedChannelCount == 3)
    }

    @Test("Authenticated Connection Resets The Connection Failure Count", .enabled(if: ServerEventCoordinator.platformSupportsWebSocket))
    func authenticatedConnectionResetsTheConnectionFailureCount() async throws {
        let failing = { MockWebSocketChannel(frames: [], closesWhenExhausted: true) }
        let dropping = MockWebSocketChannel(frames: [.text("authenticated")], closesWhenExhausted: true)
        let delivering = MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")])
        let connector = MockWebSocketConnecting(channels: [failing(), failing(), dropping, failing(), failing(), delivering])
        let server = makeServer(session: MockRequesting(string: capabilities(pushing: ["notifications"])), webSocket: connector)

        // The poll interval is far above the timeout of the test, so falling back to polling would stall the stream rather than deliver a hint which could pass for a pushed one.
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 100, emitConnectedOnStart: false), rediscoverInterval: 100)

        // Two failures precede and follow the connection which authenticated, so only resetting the count there keeps the coordinator on the socket.
        let events = try await firstEvents(3, from: stream)
        #expect(events == [.connected, .connected, .notifications])
        #expect(connector.openedChannelCount == 6)
    }

    @Test("Polls Only When Asked To")
    func pollsOnlyWhenAskedTo() async throws {
        let session = MockRequesting(string: capabilities(pushing: ["notifications"]))
        let connector = MockWebSocketConnecting(channels: [MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")])])
        let server = makeServer(session: session, webSocket: connector)
        let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 0.03, transport: .polling))

        // The server advertises notify_push, but the polling transport neither asks for the capabilities nor opens a socket.
        let events = try await firstEvents(3, from: stream)
        #expect(events == [.connected, .notifications, .notifications])
        #expect(session.requests.isEmpty)
        #expect(connector.openedChannelCount == 0)
    }

    #if os(watchOS)
        @Test("Automatic Transport Polls On watchOS")
        func automaticTransportPollsOnWatchOS() async throws {
            let session = MockRequesting(string: capabilities(pushing: ["notifications"]))
            let connector = MockWebSocketConnecting(channels: [MockWebSocketChannel(frames: [.text("authenticated"), .text("notify_notification")])])
            let server = makeServer(session: session, webSocket: connector)
            let stream = makeStream(server: server, options: ServerEventOptions(subjects: [.notifications], pollInterval: 0.03))

            // The server advertises notify_push, but watchOS does not let the app rely on a socket, so the automatic transport polls without asking for the capabilities.
            let events = try await firstEvents(3, from: stream)
            #expect(events == [.connected, .notifications, .notifications])
            #expect(session.requests.isEmpty)
            #expect(connector.openedChannelCount == 0)
        }
    #endif

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
