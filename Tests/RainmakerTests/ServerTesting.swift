// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker

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

    func makeServer(user: String? = "admin", password: String? = "admin", serverVersion: ServerVersion, testSourceCodeFile: String = #filePath, testName: String = #function) throws -> any Serving {
        let session = try URLTestSession(serverVersion: serverVersion, testSourceCodeFile: testSourceCodeFile, testName: testName)
        return Server(address: serverAddress, password: password, user: user, session: session, userAgent: "RainmakerTests")
    }
}
