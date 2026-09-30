// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
@testable import Rainmaker
import Testing

///
/// About how ``PendingPing`` turns the pong handler of `URLSessionWebSocketTask.sendPing(pongReceiveHandler:)` into exactly one resumption of the task waiting for it.
///
/// A `URLSessionWebSocketTask` cannot be substituted, so these tests stand in for it the way it behaves: the handler the ping hands out is stored, then called later, from other queues, after the waiting task has resumed, more than once, concurrently, or never.
/// Each case waits on a real `CheckedContinuation`, so a regression terminates the test process exactly as it terminated the apps shipping this library, rather than failing an assertion.
/// Every wait polls through ``eventually(within:_:)``, since a regression which ignores cancellation would otherwise hang the suite instead of failing it.
///
@Suite("Pending Ping") struct PendingPingTests {
    ///
    /// The logger the pings under test record dropped outcomes through.
    ///
    private let logger = Logger(subsystem: "RainmakerTests", category: "PendingPing")

    ///
    /// The pong handler the ping under test handed out, standing in for the `URLSessionWebSocketTask` which would keep it until reporting.
    ///
    private typealias PongHandler = @Sendable ((any Error)?) -> Void

    ///
    /// Start a task waiting on the given ping, recording the handler it sends and the outcome it ends with.
    ///
    /// - Parameters:
    ///     - ping: The ping to wait on.
    ///     - handler: Receives the pong handler once the ping is sent.
    ///     - outcome: Receives how the wait ended.
    ///     - cancelledFirst: Whether the task cancels itself before it starts waiting.
    ///
    /// - Returns: The waiting task.
    ///
    private func startWaiting(on ping: PendingPing, handler: LockedValue<PongHandler?>, outcome: LockedValue<Result<Void, any Error>?>, cancelledFirst: Bool = false) -> Task<Void, Never> {
        Task {
            if cancelledFirst {
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
            }

            do {
                try await ping.wait { pongHandler in
                    handler.set(pongHandler)
                }

                outcome.set(.success(()))
            } catch {
                outcome.set(.failure(error))
            }
        }
    }

    ///
    /// Call the given handler on a queue of its own and wait until it returned.
    ///
    private func report(_ error: (any Error)?, to handler: @escaping PongHandler, label: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue(label: label).async {
                handler(error)
                continuation.resume()
            }
        }
    }

    @Test("Delivers Only The First Of Two Outcomes", arguments: [(nil, nil), (nil, .networkConnectionLost), (.networkConnectionLost, nil), (.networkConnectionLost, .cancelled)] as [(URLError.Code?, URLError.Code?)])
    func deliversOnlyTheFirstOfTwoOutcomes(first: URLError.Code?, second: URLError.Code?) async throws {
        let ping = PendingPing(logger: logger)
        let handler = LockedValue<PongHandler?>(nil)
        let outcome = LockedValue<Result<Void, any Error>?>(nil)
        let task = startWaiting(on: ping, handler: handler, outcome: outcome)

        try #require(try await eventually { handler.get() != nil })
        let pong = try #require(handler.get())

        await report(first.map { URLError($0) }, to: pong, label: "first")
        try #require(try await eventually { outcome.get() != nil })
        await task.value

        // The framework reports again although the waiting task has long resumed, which is what terminated the process before.
        await report(second.map { URLError($0) }, to: pong, label: "second")

        switch outcome.get() {
            case .success:
                #expect(first == nil)

            case let .failure(error):
                #expect((error as? URLError)?.code == first)

            case nil:
                Issue.record("The wait never ended.")
        }
    }

    @Test("Resumes Once When Many Queues Report At Once")
    func resumesOnceWhenManyQueuesReportAtOnce() async throws {
        let ping = PendingPing(logger: logger)
        let handler = LockedValue<PongHandler?>(nil)
        let outcome = LockedValue<Result<Void, any Error>?>(nil)
        let resumptions = LockedValue(0)
        let task = startWaiting(on: ping, handler: handler, outcome: outcome)

        try #require(try await eventually { handler.get() != nil })

        DispatchQueue.concurrentPerform(iterations: 256) { iteration in
            if ping.resolve(iteration.isMultiple(of: 2) ? nil : URLError(.networkConnectionLost)) {
                resumptions.withValue { $0 += 1 }
            }
        }

        try #require(try await eventually { outcome.get() != nil })
        await task.value
        #expect(resumptions.get() == 1)
    }

    @Test("Survives Cancellation Racing Concurrent Reports")
    func survivesCancellationRacingConcurrentReports() async throws {
        for _ in 0 ..< 300 {
            let ping = PendingPing(logger: logger)
            let handler = LockedValue<PongHandler?>(nil)
            let outcome = LockedValue<Result<Void, any Error>?>(nil)
            let task = startWaiting(on: ping, handler: handler, outcome: outcome)

            try #require(try await eventually { handler.get() != nil })
            let pong = try #require(handler.get())

            DispatchQueue.concurrentPerform(iterations: 8) { iteration in
                if iteration == 0 {
                    task.cancel()
                } else {
                    pong(iteration.isMultiple(of: 2) ? nil : URLError(.networkConnectionLost))
                }
            }

            try #require(try await eventually { outcome.get() != nil })
            await task.value
        }
    }

    @Test("Does Not Send A Ping For A Cancelled Task")
    func doesNotSendAPingForACancelledTask() async throws {
        let ping = PendingPing(logger: logger)
        let handler = LockedValue<PongHandler?>(nil)
        let outcome = LockedValue<Result<Void, any Error>?>(nil)
        let task = startWaiting(on: ping, handler: handler, outcome: outcome, cancelledFirst: true)

        try #require(try await eventually { outcome.get() != nil })
        await task.value
        #expect(handler.get() == nil)

        guard case let .failure(error) = outcome.get() else {
            Issue.record("A cancelled task sent its ping and waited.")
            return
        }

        #expect(error is CancellationError)
    }

    @Test("Cancellation Ends The Wait For A Pong That Never Arrives")
    func cancellationEndsTheWaitForAPongThatNeverArrives() async throws {
        let ping = PendingPing(logger: logger)
        let handler = LockedValue<PongHandler?>(nil)
        let outcome = LockedValue<Result<Void, any Error>?>(nil)
        let task = startWaiting(on: ping, handler: handler, outcome: outcome)

        try #require(try await eventually { handler.get() != nil })
        let pong = try #require(handler.get())

        task.cancel()
        try #require(try await eventually { outcome.get() != nil })
        await task.value

        // Closing the connection makes the framework report the ping it still had outstanding, which must be dropped.
        await report(URLError(.cancelled), to: pong, label: "late")
        #expect(ping.resolve(nil) == false)

        guard case let .failure(error) = outcome.get() else {
            Issue.record("A cancelled ping reported success.")
            return
        }

        #expect(error is CancellationError)
    }
}
