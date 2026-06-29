// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
@testable import Rainmaker
import RainmakerTestServerTags

///
/// A recording implementation of `Requesting` which performs requests against a live server and writes the responses into the fixture tree consumed by ``URLTestSession``.
///
/// It is the inverse of ``URLTestSession``: where the latter reads fixtures from the test bundle, this performs the real request, captures its response, and writes it into the source tree using the same ``FixtureLocator`` so that recording and replay can never derive different paths. The live response is returned to the caller unchanged so that the test's assertions run against real server behavior, while only a canonicalized copy is persisted.
///
public actor URLRecordingSession: Requesting {
    let logger: Logger

    ///
    /// The session performing the actual network requests against the live server.
    ///
    let session: URLSession

    ///
    /// Derives the on-disk fixture locations this session writes to, rooted at the `Responses` directory in the source tree.
    ///
    let locator: FixtureLocator

    ///
    /// Normalizes recorded responses so that fixtures stay stable across regenerations.
    ///
    let canonicalizer: FixtureCanonicalizer

    ///
    /// The directory holding all fixtures for the test this instance records.
    ///
    let testDirectory: URL

    public init(serverVersion: ServerVersion, liveServerAddress: URL, testSourceCodeFile: String = #filePath, testName: String = #function) {
        logger = Logger(OSLog(subsystem: "RainmakerTests", category: "URLRecordingSession"))
        session = URLSession(configuration: .ephemeral)

        // The fixtures are written into the source tree next to the test files, derived from the test's own source location, so they end up exactly where the test bundle copies them from.
        let responsesRoot = URL(fileURLWithPath: testSourceCodeFile)
            .deletingLastPathComponent()
            .appendingCompatibility(component: "Responses")

        let locator = FixtureLocator(responsesRoot: responsesRoot)
        self.locator = locator

        let suiteName = FixtureLocator.suiteName(fromSourceCodeFile: testSourceCodeFile)
        let sanitizedTestName = FixtureLocator.testName(fromFunction: testName)
        testDirectory = locator.testDirectory(serverVersion: serverVersion, suiteName: suiteName, testName: sanitizedTestName)

        canonicalizer = FixtureCanonicalizer(liveServerAddress: liveServerAddress)

        // swiftformat:disable:next redundantSelf
        logger.debug("Recording into \"\(self.testDirectory.percentEncodedPath)\".")
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, urlResponse) = try await session.data(for: request)
        let (method, url, response) = try Self.components(of: request, urlResponse)

        guard let acceptedType = request.allHTTPHeaderFields?["Accept"] else {
            throw URLRecordingSessionError.missingValue
        }

        let bodyExtension = try FixtureLocator.bodyExtension(forAcceptHeader: acceptedType)
        let body = canonicalizer.canonicalizedBody(data, pathExtension: bodyExtension)
        try record(method: method, url: url, response: response, body: body, bodyExtension: bodyExtension)

        return (data, urlResponse)
    }

    public func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        let (location, urlResponse) = try await session.download(for: request, delegate: delegate)
        let (method, url, response) = try Self.components(of: request, urlResponse)

        let data = try Data(contentsOf: location)
        let body = canonicalizer.canonicalizedBody(data, pathExtension: "bin")
        try record(method: method, url: url, response: response, body: body, bodyExtension: "bin")

        return (location, urlResponse)
    }

    public func upload(for request: URLRequest, fromFile fileURL: URL, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        let (data, urlResponse) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
        let (method, url, response) = try Self.components(of: request, urlResponse)

        // The response body of an upload carries no payload relevant to the client, so only the headers are recorded, matching what ``URLTestSession`` replays.
        try record(method: method, url: url, response: response, body: nil, bodyExtension: nil)

        return (data, urlResponse)
    }

    // MARK: - Private

    ///
    /// Extracts the request method, request URL, and the response cast to `HTTPURLResponse`, throwing when any of them is missing.
    ///
    private static func components(of request: URLRequest, _ urlResponse: URLResponse) throws -> (method: String, url: URL, response: HTTPURLResponse) {
        guard let method = request.httpMethod, let url = request.url else {
            throw URLRecordingSessionError.missingValue
        }

        guard let response = urlResponse as? HTTPURLResponse else {
            throw URLRecordingSessionError.unexpectedResponseType
        }

        return (method, url, response)
    }

    ///
    /// Writes the headers and, when present, the body of a captured response into the fixture tree.
    ///
    /// Paths are taken from ``FixtureLocator`` and written via their percent-encoded representation so that the files end up exactly where ``URLTestSession`` reads them from, even for paths containing special characters.
    ///
    private func record(method: String, url: URL, response: HTTPURLResponse, body: Data?, bodyExtension: String?) throws {
        let requestDirectory = locator.requestDirectory(in: testDirectory, method: method, url: url)
        try FileManager.default.createDirectory(atPath: requestDirectory.percentEncodedPath, withIntermediateDirectories: true)

        let headersData = canonicalizer.headersText(statusCode: response.statusCode, headerFields: response.allHeaderFields)
        let headersPath = locator.headersFile(in: requestDirectory).percentEncodedPath

        guard FileManager.default.createFile(atPath: headersPath, contents: headersData) else {
            throw URLRecordingSessionError.writeFailed(headersPath)
        }

        logger.debug("Recorded headers at \"\(headersPath)\".")

        if let body, let bodyExtension {
            let bodyPath = locator.bodyFile(in: requestDirectory, pathExtension: bodyExtension).percentEncodedPath

            guard FileManager.default.createFile(atPath: bodyPath, contents: body) else {
                throw URLRecordingSessionError.writeFailed(bodyPath)
            }

            logger.debug("Recorded body at \"\(bodyPath)\".")
        }
    }
}
