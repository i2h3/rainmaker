// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Features of `URLSession` defined as a mockable protocol for tests.
///
protocol Requesting: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
