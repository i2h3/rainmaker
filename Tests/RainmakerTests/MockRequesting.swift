// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A ``Requesting`` test double returning a fixed body and status for every request, used to feed ``Server/capabilities()`` a canned response in the server-events tests without touching the fixture tree.
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
    /// Create a mock returning the given body and status.
    ///
    /// - Parameters:
    ///     - body: The response body.
    ///     - statusCode: The HTTP status code. Defaults to 200.
    ///
    init(body: Data, statusCode: Int = 200) {
        self.body = body
        self.statusCode = statusCode
    }

    ///
    /// Create a mock returning the given string as a UTF-8 body and the given status.
    ///
    /// - Parameters:
    ///     - string: The response body as a string.
    ///     - statusCode: The HTTP status code. Defaults to 200.
    ///
    convenience init(string: String, statusCode: Int = 200) {
        self.init(body: Data(string.utf8), statusCode: statusCode)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    func download(for _: URLRequest, delegate _: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        throw MockWebSocketError.closed
    }

    func upload(for _: URLRequest, fromFile _: URL, delegate _: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        throw MockWebSocketError.closed
    }
}
