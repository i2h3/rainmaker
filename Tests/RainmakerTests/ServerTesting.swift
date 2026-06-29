// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags

///
/// Helpers for tests.
///
protocol ServerTesting {
    ///
    /// Mock server address.
    ///
    var serverAddress: URL { get }

    ///
    /// Mock a server object for tests.
    ///
    func makeServer(user: String?, password: String?, serverVersion: ServerVersion, testSourceCodeFile: String, testName: String) throws -> any Serving
}

extension ServerTesting {
    var serverAddress: URL {
        URL(string: "http://localhost/")!
    }

    ///
    /// Builds the server a test runs against, transparently selecting between replaying fixtures and recording them.
    ///
    /// By default the returned server is backed by ``URLTestSession`` and reads static fixtures, so tests never touch a network. When the `RAINMAKER_FIXTURE_RECORD` environment variable is set, it is instead backed by ``URLRecordingSession`` and points at the live server given by `RAINMAKER_FIXTURE_SERVER`, capturing fresh fixtures into the source tree. This single seam keeps the test bodies the only definition of which requests a fixture set needs.
    ///
    func makeServer(user: String? = "admin", password: String? = "admin", serverVersion: ServerVersion, testSourceCodeFile: String = #filePath, testName: String = #function) throws -> any Serving {
        let environment = ProcessInfo.processInfo.environment

        if environment["RAINMAKER_FIXTURE_RECORD"] != nil {
            guard let serverString = environment["RAINMAKER_FIXTURE_SERVER"], let liveServerAddress = URL(string: serverString) else {
                throw RainmakerTestsError.invalidRecordingServer
            }

            let session = URLRecordingSession(serverVersion: serverVersion, liveServerAddress: liveServerAddress, testSourceCodeFile: testSourceCodeFile, testName: testName)
            return Server(address: liveServerAddress, password: password, user: user, session: session, userAgent: "RainmakerTests")
        }

        let session = try URLTestSession(serverVersion: serverVersion, testSourceCodeFile: testSourceCodeFile, testName: testName)
        return Server(address: serverAddress, password: password, user: user, session: session, userAgent: "RainmakerTests")
    }
}
