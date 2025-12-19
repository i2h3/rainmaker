// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

///
/// A hand-written mock implementation of ``Serving`` for use in tests.
///
public final class ServingMock: Serving, @unchecked Sendable {
    // MARK: - Serving

    public let address: URL
    public let password: String
    public let user: String

    public init(address: URL, password: String, user: String) {
        self.address = address
        self.password = password
        self.user = user
    }

    public func enumerate(at path: String, recursively: Bool) async throws -> AsyncThrowingStream<Item, Error> {
        let key = EnumerateKey(path: path, recursively: recursively)

        guard let handler = mockedEnumerations[key] else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        return try await handler()
    }

    // MARK: - Mock

    private struct EnumerateKey: Hashable {
        let path: String
        let recursively: Bool
    }

    private typealias EnumerateHandler = @Sendable () async throws -> AsyncThrowingStream<Item, Error>

    private var mockedEnumerations: [EnumerateKey: EnumerateHandler] = [:]

    public func mockEnumerateReturnValue(_ items: [Item], for path: String, recursively: Bool) {
        mockedEnumerations[EnumerateKey(path: path, recursively: recursively)] = {
            AsyncThrowingStream { continuation in
                for item in items {
                    continuation.yield(item)
                }

                continuation.finish()
            }
        }
    }

    public func mockEnumerateThrowing(_ error: Error, for path: String, recursively: Bool) {
        mockedEnumerations[EnumerateKey(path: path, recursively: recursively)] = {
            throw error
        }
    }
}
