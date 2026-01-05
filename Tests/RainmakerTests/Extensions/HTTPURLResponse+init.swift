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
    ///     - file: The fixture to parse for the values.
    ///
    convenience init?(from file: URL, for request: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path()) else {
            throw RainmakerTestsError.missingFixture(file)
        }

        let data = try Data(contentsOf: file)

        guard let text = String(data: data, encoding: .utf8) else {
            throw RainmakerTestsError.decodingError(file)
        }

        let lines = text.split(separator: "\n")

        guard let status = lines.first?.split(separator: " ") else {
            throw RainmakerTestsError.decodingError(file)
        }

        let httpVersion = String(status[0])

        guard let statusCode = Int(status[1]) else {
            throw RainmakerTestsError.decodingError(file)
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

