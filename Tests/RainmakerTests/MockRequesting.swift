// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A ``Requesting`` test double returning a fixed body, status and header fields for every request, used to feed a canned response to code under test without touching the fixture tree.
///
/// Every request it receives is captured in ``requests``, which is what makes it usable as a spy for assertions on how a request was built. The fixture tree cannot serve that purpose because ``FixtureLocator`` keys fixtures by method and path alone and therefore ignores the query string entirely.
///
final class MockRequesting: Requesting, @unchecked Sendable {
    ///
    /// The response body returned for every request.
    ///
    private let body: Data

    ///
    /// The HTTP status code returned for every request.
    ///
    private let statusCode: Int

    ///
    /// The header fields returned for every request.
    ///
    private let headerFields: [String: String]?

    ///
    /// Guards ``capturedRequests`` because a ``Server`` may issue requests from more than one task.
    ///
    private let lock = NSLock()

    ///
    /// The requests received so far, in order.
    ///
    private var capturedRequests = [URLRequest]()

    ///
    /// The requests this mock received so far, in the order they were issued.
    ///
    var requests: [URLRequest] {
        lock.lock()

        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    ///
    /// Create a mock returning the given body and status.
    ///
    /// - Parameters:
    ///     - body: The response body.
    ///     - statusCode: The HTTP status code. Defaults to 200.
    ///     - headerFields: The response header fields. Defaults to none.
    ///
    init(body: Data, statusCode: Int = 200, headerFields: [String: String]? = nil) {
        self.body = body
        self.statusCode = statusCode
        self.headerFields = headerFields
    }

    ///
    /// Create a mock returning the given string as a UTF-8 body and the given status.
    ///
    /// - Parameters:
    ///     - string: The response body as a string.
    ///     - statusCode: The HTTP status code. Defaults to 200.
    ///     - headerFields: The response header fields. Defaults to none.
    ///
    convenience init(string: String, statusCode: Int = 200, headerFields: [String: String]? = nil) {
        self.init(body: Data(string.utf8), statusCode: statusCode, headerFields: headerFields)
    }

    ///
    /// Record a request, from a synchronous context because the lock may not be taken from an asynchronous one.
    ///
    private func capture(_ request: URLRequest) {
        lock.lock()

        defer {
            lock.unlock()
        }

        capturedRequests.append(request)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capture(request)

        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headerFields)!
        return (body, response)
    }

    func download(for _: URLRequest, delegate _: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        throw MockWebSocketError.closed
    }

    func upload(for _: URLRequest, fromFile _: URL, delegate _: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        throw MockWebSocketError.closed
    }
}
