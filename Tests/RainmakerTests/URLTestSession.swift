// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
@testable import Rainmaker

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

        let serverVersionResources = resources.appendingCompatibility(component: "Responses").appendingCompatibility(component: serverVersion.rawValue)

        guard FileManager.default.fileExists(atPath: serverVersionResources.compatibilityPath()) else {
            logger.fault("Not found: \(serverVersionResources.compatibilityPath())")
            throw URLTestSessionError.serverVersionNotFound
        }

        let suiteName = URL(fileURLWithPath: testSourceCodeFile).deletingPathExtension().lastPathComponent
        let suiteResources = serverVersionResources.appendingCompatibility(component: suiteName)

        guard FileManager.default.fileExists(atPath: suiteResources.compatibilityPath()) else {
            logger.fault("Not found: \(suiteResources.compatibilityPath())")
            throw URLTestSessionError.suiteNotFound
        }

        let sanitizedTestName = testName.prefix(upTo: testName.firstIndex(of: "(") ?? testName.endIndex)
        let testResources = suiteResources.appendingCompatibility(component: sanitizedTestName)
        self.testName = testName

        if FileManager.default.fileExists(atPath: testResources.compatibilityPath()) {
            self.testResources = testResources
        } else {
            self.testResources = nil
            logger.debug("Not found: \(testResources.compatibilityPath())")
        }

        // swiftformat:disable:next redundantSelf
        logger.debug("Initialized for suite name \"\(suiteName)\" and test name \"\(testName)\", derived resource path \"\(self.testResources?.compatibilityPath() ?? "nil")\".")
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

        let requestPath = url.compatibilityPath(percentEncoded: false)

        let requestResources = testResources
            .appendingCompatibility(component: method)
            .appendingCompatibility(path: requestPath)

        let headersFile = requestResources
            .appendingCompatibility(component: "Headers")
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
            .appendingCompatibility(component: "Body")
            .appendingPathExtension(bodyFileExtension)

        logger.debug("Assuming body file: \(bodyFile.percentEncodedPath)")
        let bodyData = try readDataFromPercentEncodedPath(at: bodyFile)

        guard let httpResponse = try HTTPURLResponse(from: headersData, for: url) else {
            throw URLTestSessionError.missingValue
        }

        return (bodyData, httpResponse)
    }

    public func download(for request: URLRequest, delegate _: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        guard let testResources else {
            throw URLTestSessionError.testNotFound
        }

        guard let method = request.httpMethod else {
            throw URLTestSessionError.missingValue
        }

        guard let url = request.url else {
            throw URLTestSessionError.missingValue
        }

        let requestPath = url.compatibilityPath(percentEncoded: false)

        let requestResources = testResources
            .appendingCompatibility(component: method)
            .appendingCompatibility(path: requestPath)

        let headersFile = requestResources
            .appendingCompatibility(component: "Headers")
            .appendingPathExtension("txt")

        logger.debug("Assuming headers file: \(headersFile.percentEncodedPath)")
        let headersData = try readDataFromPercentEncodedPath(at: headersFile)

        let bodyFile = requestResources
            .appendingCompatibility(component: "Body")
            .appendingPathExtension("bin")

        logger.debug("Assuming body file: \(bodyFile.percentEncodedPath)")
        let bodyData = try readDataFromPercentEncodedPath(at: bodyFile)

        guard let httpResponse = try HTTPURLResponse(from: headersData, for: url) else {
            throw URLTestSessionError.missingValue
        }

        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingCompatibility(component: UUID().uuidString)
        try bodyData.write(to: temporaryFile)

        return (temporaryFile, httpResponse)
    }

    public func upload(for request: URLRequest, fromFile _: URL, delegate _: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        guard let testResources else {
            throw URLTestSessionError.testNotFound
        }

        guard let method = request.httpMethod else {
            throw URLTestSessionError.missingValue
        }

        guard let url = request.url else {
            throw URLTestSessionError.missingValue
        }

        let requestPath = url.compatibilityPath(percentEncoded: false)

        let requestResources = testResources
            .appendingCompatibility(component: method)
            .appendingCompatibility(path: requestPath)

        let headersFile = requestResources
            .appendingCompatibility(component: "Headers")
            .appendingPathExtension("txt")

        logger.debug("Assuming headers file: \(headersFile.percentEncodedPath)")
        let headersData = try readDataFromPercentEncodedPath(at: headersFile)

        guard let httpResponse = try HTTPURLResponse(from: headersData, for: url) else {
            throw URLTestSessionError.missingValue
        }

        // The server response body to an upload carries no payload relevant to the client, so only the status from the headers file is replayed.
        return (Data(), httpResponse)
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

        return try handle.readToEnd() ?? Data()
    }
}
