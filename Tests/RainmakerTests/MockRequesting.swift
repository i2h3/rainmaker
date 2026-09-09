// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A ``Requesting`` test double answering every request from a responder, used to feed canned responses to code under test without touching the fixture tree.
///
/// Every request it receives is captured in ``requests``, which is what makes it usable as a spy for assertions on how a request was built. The fixture tree cannot serve that purpose because ``FixtureLocator`` keys fixtures by method and path alone and therefore ignores the query string entirely, and because ``URLTestSession`` never looks at the bytes of an upload.
///
/// The simplest mocks answer every request the same way through ``init(body:statusCode:headerFields:)``. A flow of several requests which have to be answered differently, such as a chunked upload, gets a ``Responder`` through ``init(responder:)`` instead.
///
final class MockRequesting: Requesting, @unchecked Sendable {
    ///
    /// Builds the response to a request, for mocks whose answer depends on the request.
    ///
    typealias Responder = @Sendable (URLRequest) -> (body: Data, statusCode: Int, headerFields: [String: String]?)

    ///
    /// Produces the body, status and header fields returned for a request.
    ///
    private let responder: Responder

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
    /// A request received through ``upload(for:fromFile:delegate:)`` carries the bytes of the uploaded file in its `httpBody`, which a real session leaves empty for a file upload, so that a test can assert on what would have been sent.
    ///
    var requests: [URLRequest] {
        lock.lock()

        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    ///
    /// Create a mock answering every request through the given responder.
    ///
    /// - Parameters:
    ///     - responder: Builds the response to each request.
    ///
    init(responder: @escaping Responder) {
        self.responder = responder
    }

    ///
    /// Create a mock returning the given body and status for every request.
    ///
    /// - Parameters:
    ///     - body: The response body.
    ///     - statusCode: The HTTP status code. Defaults to 200.
    ///     - headerFields: The response header fields. Defaults to none.
    ///
    convenience init(body: Data, statusCode: Int = 200, headerFields: [String: String]? = nil) {
        self.init { _ in
            (body, statusCode, headerFields)
        }
    }

    ///
    /// Create a mock returning the given string as a UTF-8 body and the given status for every request.
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

    ///
    /// Build the canned response to a request from what the responder says about it.
    ///
    private func answer(_ request: URLRequest) -> (Data, URLResponse) {
        let answer = responder(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.statusCode, httpVersion: nil, headerFields: answer.headerFields)!
        return (answer.body, response)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capture(request)
        return answer(request)
    }

    func download(for _: URLRequest, delegate _: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        throw MockWebSocketError.closed
    }

    func upload(for request: URLRequest, fromFile fileURL: URL, delegate _: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        // The file is read right away because the caller may remove it as soon as this returns, as ``Server`` does with a staged chunk.
        var captured = request
        captured.httpBody = try Data(contentsOf: fileURL)
        capture(captured)
        return answer(request)
    }
}
