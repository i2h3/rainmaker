// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
@testable import Rainmaker
import Synchronization

///
/// A mock implementation of `URLSession` to return static responses from the test bundle resources.
///
public actor URLTestSession: Requesting {
    let logger: Logger
    let resourcePath: URL?
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
        self.testName = testName

        if FileManager.default.fileExists(atPath: testResources.path()) {
            resourcePath = testResources
        } else {
            resourcePath = nil
            logger.debug("Not found: \(testResources.path())")
        }

        // swiftformat:disable:next redundantSelf
        logger.debug("Initialized for suite name \"\(suiteName)\" and test name \"\(testName)\", derived resource path \"\(self.resourcePath?.path() ?? "nil")\".")
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        logger.debug("Data request for: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "nil")")

        guard let resourcePath else {
            throw URLTestSessionError.testNotFound
        }

        guard let method = request.httpMethod else {
            throw URLTestSessionError.missingValue
        }

        guard let url = request.url else {
            throw URLTestSessionError.missingValue
        }

        guard let acceptedType = request.allHTTPHeaderFields?["Accept"] else {
            throw URLTestSessionError.missingAcceptHeader
        }

        let pathExtension = switch acceptedType {
            case "application/json":
                "json"
            case "application/xml":
                "xml"
            default:
                throw URLTestSessionError.unsupportedResponseType
        }

        let resource = resourcePath
            .appending(component: method)
            .appending(path: url.path())
            .appending(component: "Response")
            .appendingPathExtension(pathExtension)
            .standardized

        if FileManager.default.fileExists(atPath: resource.path(percentEncoded: false)) == false {
            throw URLTestSessionError.resourceNotFound(resource)
        }

        let data = try Data(contentsOf: resource)
        let httpResponse = HTTPURLResponse(url: request.url ?? resource, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        logger.debug("Returning content of \(resource.path())")

        return (data, httpResponse)
    }
}
