// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension HTTPURLResponse {
    ///
    /// Try to create an instance based on the given plain text file which contains raw HTTP response headers.
    ///
    /// This is a very simple implementation based on basic string operations due to the relatively simple use case.
    /// More comprehensive and robust implementations by others have been left out intentionally for now.
    ///
    /// - Parameters:
    ///     - data: The raw HTTP response header data to parse.
    ///     - request: The original URL request this information is supposed to be initialized for.
    ///
    convenience init?(from data: Data, for request: URL) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RainmakerTestsError.decodingError(request)
        }

        let lines = text.split(separator: "\n")

        guard let status = lines.first?.split(separator: " ") else {
            throw RainmakerTestsError.decodingError(request)
        }

        let httpVersion = String(status[0])

        guard let statusCode = Int(status[1]) else {
            throw RainmakerTestsError.decodingError(request)
        }

        var headerFields = [String: String]()

        for line in lines[1...] {
            guard let delimiter = line.firstIndex(of: ":") else {
                continue
            }

            let key = String(line.prefix(upTo: delimiter).trimmingCharacters(in: .whitespacesAndNewlines))
            let value = String(line.suffix(from: line.index(delimiter, offsetBy: 1)).trimmingCharacters(in: .whitespacesAndNewlines))

            headerFields[key] = value
        }

        self.init(url: request, statusCode: statusCode, httpVersion: httpVersion, headerFields: headerFields)
    }
}
