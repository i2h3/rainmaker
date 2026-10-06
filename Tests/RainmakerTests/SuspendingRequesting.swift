// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A ``Requesting`` test double which answers a given number of requests through a ``MockRequesting`` and keeps every request after those in flight until the task which sent it is cancelled.
///
/// Data requests and uploads count alike, while downloads are answered unless ``suspendsDownloads`` says to count and suspend them as well.
///
/// A ``MockRequesting`` answers synchronously, so it cannot prove that cancelling a task cancels the request that task is waiting for. This double can: a suspended request ends as a `URLSession` data task does when its task is cancelled, by throwing `URLError.cancelled`, and a request whose task is never cancelled never ends.
///
final class SuspendingRequesting: Requesting, @unchecked Sendable {
    ///
    /// Answers the requests before the suspended ones and captures them in its ``MockRequesting/requests``.
    ///
    let answering: MockRequesting

    ///
    /// The number of requests answered through ``answering`` before every further request is suspended.
    ///
    private let answeredCount: Int

    ///
    /// Whether downloads are counted and suspended like data requests and uploads rather than always answered, which a test of cancelling ``Server/downloadAttachment(at:ofNote:to:force:)`` needs.
    ///
    private let suspendsDownloads: Bool

    ///
    /// The number of requests received so far and the number of them currently suspended, which tests wait on through ``eventually(within:_:)``.
    ///
    private let counts = LockedValue((received: 0, suspended: 0))

    ///
    /// The number of requests currently suspended, waiting for their task to be cancelled.
    ///
    var suspendedCount: Int {
        counts.get().suspended
    }

    ///
    /// The number of requests received so far, the suspended ones included.
    ///
    var receivedCount: Int {
        counts.get().received
    }

    ///
    /// Create a double answering the given number of requests before suspending every further one.
    ///
    /// - Parameters:
    ///     - answeredCount: The number of requests answered through `answering`.
    ///     - answering: The mock which answers those requests.
    ///     - suspendsDownloads: Whether downloads count and are suspended like the other requests. Defaults to `false`.
    ///
    init(answering answeredCount: Int, through answering: MockRequesting, suspendsDownloads: Bool = false) {
        self.answeredCount = answeredCount
        self.answering = answering
        self.suspendsDownloads = suspendsDownloads
    }

    ///
    /// The local files the uploads received so far were to be sent from, the suspended ones included, which a test checks to have been removed once an upload was cancelled.
    ///
    private let receivedUploadSources = LockedValue([URL]())

    ///
    /// The local files the uploads received so far were to be sent from, in order, the suspended ones included.
    ///
    var uploadSources: [URL] {
        receivedUploadSources.get()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard receive() else {
            return try await answering.data(for: request)
        }

        try await suspend()
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        guard suspendsDownloads, receive() else {
            return try await answering.download(for: request, delegate: delegate)
        }

        try await suspend()
    }

    func upload(for request: URLRequest, fromFile fileURL: URL, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        receivedUploadSources.withValue { $0.append(fileURL) }

        guard receive() else {
            return try await answering.upload(for: request, fromFile: fileURL, delegate: delegate)
        }

        try await suspend()
    }

    ///
    /// Count a received request and tell whether it is one to suspend rather than to answer.
    ///
    private func receive() -> Bool {
        let index = counts.withValue { counts in
            counts.received += 1
            return counts.received
        }

        return index > answeredCount
    }

    ///
    /// Keep the calling request in flight until its task is cancelled, then end it as a `URLSession` task ends, by throwing `URLError.cancelled`.
    ///
    private func suspend() async throws -> Never {
        counts.withValue { $0.suspended += 1 }

        defer {
            counts.withValue { $0.suspended -= 1 }
        }

        // An hour stands in for a request which never completes on its own, while cancelling the task ends the sleep right away.
        do {
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        } catch {
            throw URLError(.cancelled)
        }

        throw URLError(.timedOut)
    }
}
