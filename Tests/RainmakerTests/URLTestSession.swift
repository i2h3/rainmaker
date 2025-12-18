// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Synchronization
@testable import Rainmaker

///
/// A mock implementation of `URLSession` to return static responses from the test bundle resources.
///
public final class URLTestSession: Requesting, Sendable {
    private let requestNumber = OSAllocatedUnfairLock(initialState: 0)

    let logger: Logger
    let resourcePath: URL
    let testName: String

    public init(serverVersion: ServerVersion, testSourceCodeFile: String = #filePath, testName: String = #function) throws {
        logger = Logger(OSLog(subsystem: "RainmakerTests", category: "URLTestSession"))

        guard let resources = Bundle.module.resourceURL else {
            throw URLTestSessionError.resourcesNotFound
        }

        let serverVersionResources = resources.appending(component: "Responses").appending(component: serverVersion.rawValue)

        guard FileManager.default.fileExists(atPath: serverVersionResources.path()) else {
            logger.fault("Not found: \(serverVersionResources.path())")
            throw URLTestSessionError.serverVersionNotFound
        }

        let suiteName = URL(filePath: testSourceCodeFile).deletingPathExtension().lastPathComponent
        let suiteResources = serverVersionResources.appending(component: suiteName)

        guard FileManager.default.fileExists(atPath: suiteResources.path()) else {
            logger.fault("Not found: \(suiteResources.path())")
            throw URLTestSessionError.suiteNotFound
        }

        let sanitizedTestName = testName.prefix(upTo: testName.firstIndex(of: "(") ?? testName.endIndex)
        let testResources = suiteResources.appending(component: sanitizedTestName)

        guard FileManager.default.fileExists(atPath: testResources.path()) else {
            logger.fault("Not found: \(testResources.path())")
            throw URLTestSessionError.testNotFound
        }

        resourcePath = testResources
        self.testName = testName

        // swiftformat:disable:next redundantSelf
        logger.debug("Initialized for suite name \"\(suiteName)\" and test name \"\(testName)\", derived resource path \"\(self.resourcePath.path())\".")
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let currentRequestNumber = requestNumber.withLock { value in
            value += 1
            return value
        }
        let resource = resourcePath.appending(component: "\(currentRequestNumber).xml")
        logger.debug("Reading content of \(resource.path())")
        let data = try Data(contentsOf: resource)
        let httpResponse = HTTPURLResponse(url: request.url ?? resource, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!

        return (data, httpResponse)
    }
}
