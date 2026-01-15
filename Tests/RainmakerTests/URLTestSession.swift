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

    ///
    /// The root location of all resources related to the test this instance is initialized for.
    ///
    let testResources: URL?

    ///
    /// The test case name, usually derived automatically from the calling test method.
    ///
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
            self.testResources = testResources
        } else {
            self.testResources = nil
            logger.debug("Not found: \(testResources.path())")
        }

        // swiftformat:disable:next redundantSelf
        logger.debug("Initialized for suite name \"\(suiteName)\" and test name \"\(testName)\", derived resource path \"\(self.testResources?.path() ?? "nil")\".")
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let testResources else {
            throw URLTestSessionError.testNotFound
        }

        guard let method = request.httpMethod else {
            throw URLTestSessionError.missingValue
        }

        guard let url = request.url else {
            throw URLTestSessionError.missingValue
        }

        let requestPath = url.path(percentEncoded: false)

        let requestResources = testResources
            .appending(component: method)
            .appending(path: requestPath)

        let headersFile = requestResources
            .appending(component: "Headers")
            .appendingPathExtension("txt")

        logger.debug("Assuming headers file: \(headersFile.percentEncodedPath)")
        let headersData = try readDataFromPercentEncodedPath(at: headersFile)

        guard let acceptedType = request.allHTTPHeaderFields?["Accept"] else {
            throw URLTestSessionError.missingAcceptHeader
        }

        let bodyFileExtension = switch acceptedType {
            case "application/json":
                "json"
            case "application/xml":
                "xml"
            default:
                throw URLTestSessionError.unsupportedResponseType
        }

        let bodyFile = requestResources
            .appending(component: "Body")
            .appendingPathExtension(bodyFileExtension)

        logger.debug("Assuming body file: \(bodyFile.percentEncodedPath)")
        let bodyData = try readDataFromPercentEncodedPath(at: bodyFile)

        guard let httpResponse = try HTTPURLResponse(from: headersData, for: url) else {
            throw URLTestSessionError.missingValue
        }

        return (bodyData, httpResponse)
    }

    ///
    /// To have a safe and consistent path conversion for fixture files based on request paths, this is required to avoid double encoding as it may happen when loading `Data` directly from a `URL` with the designated initializer.
    ///
    private func readDataFromPercentEncodedPath(at location: URL) throws -> Data {
        let path = location.percentEncodedPath

        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw URLTestSessionError.resourceNotFound(path)
        }

        defer {
            try? handle.close()
        }

        let data = try handle.readToEnd() ?? Data()

        return data
    }
}
