// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags

///
/// Derives the on-disk locations of test response fixtures from the attributes of a request.
///
/// This single type is shared by both the fixture reader ``URLTestSession`` and the fixture writer ``URLRecordingSession`` so that the path a fixture is recorded to is always identical to the path it is later read from. It relies on the package's URL compatibility helpers so that it builds the same paths on the older platforms the package supports.
///
struct FixtureLocator {
    ///
    /// The root directory containing one subdirectory per server version.
    ///
    /// When reading this is the bundled `Responses` directory, when recording it is its counterpart in the source tree.
    ///
    let responsesRoot: URL

    ///
    /// The directory holding all fixtures for a single test of a single server version.
    ///
    /// The layout mirrors the parameters which identify a test: `<responsesRoot>/<serverVersion>/<suiteName>/<testName>`.
    ///
    func testDirectory(serverVersion: ServerVersion, suiteName: String, testName: String) -> URL {
        responsesRoot
            .appendingCompatibility(component: serverVersion.rawValue)
            .appendingCompatibility(component: suiteName)
            .appendingCompatibility(component: testName)
    }

    ///
    /// The directory holding the fixtures of one specific request issued during a test.
    ///
    /// The request method and its decoded URL path are appended so that every distinct request maps to its own directory, mirroring the structure of the remote server.
    ///
    func requestDirectory(in testDirectory: URL, method: String, url: URL) -> URL {
        testDirectory
            .appendingCompatibility(component: method)
            .appendingCompatibility(path: url.compatibilityPath(percentEncoded: false))
    }

    ///
    /// The file holding the raw HTTP response headers of a request.
    ///
    func headersFile(in requestDirectory: URL) -> URL {
        requestDirectory
            .appendingCompatibility(component: "Headers")
            .appendingPathExtension("txt")
    }

    ///
    /// The file holding the raw HTTP response body of a request.
    ///
    func bodyFile(in requestDirectory: URL, pathExtension: String) -> URL {
        requestDirectory
            .appendingCompatibility(component: "Body")
            .appendingPathExtension(pathExtension)
    }

    ///
    /// Derives the suite name from the path of the Swift source file a test is implemented in.
    ///
    /// This matches the file name without its extension, e.g. `"DeleteTests"` for a test declared in `".../DeleteTests.swift"`.
    ///
    static func suiteName(fromSourceCodeFile path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    ///
    /// Derives the test name from the name of the test method.
    ///
    /// Everything from the first opening parenthesis onwards is dropped so that `"file(_:)"` collapses to `"file"`.
    ///
    static func testName(fromFunction function: String) -> String {
        String(function.prefix(upTo: function.firstIndex(of: "(") ?? function.endIndex))
    }

    ///
    /// Maps the `Accept` header value of a request to the file extension of the recorded response body.
    ///
    /// Binary downloads do not carry such a header and always use the `bin` extension, so they bypass this mapping.
    ///
    static func bodyExtension(forAcceptHeader acceptHeader: String) throws -> String {
        switch acceptHeader {
            case "application/json":
                "json"
            case "application/xml":
                "xml"
            default:
                throw URLTestSessionError.unsupportedResponseType
        }
    }
}
