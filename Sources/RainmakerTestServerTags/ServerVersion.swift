// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Server releases the test suite covers, identified by their Docker image tag.
///
/// This is the single source of truth for the supported versions: the test target parameterizes its tests over ``allCases``, and the `record-fixtures` tool deploys a container per case. It lives in its own small module so both the tests and the command line tool can share it without either depending on the other.
///
public enum ServerVersion: String, CaseIterable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    ///
    /// 31.0.14
    ///
    case v31_0_14 = "31.0.14"

    ///
    /// 32.0.11
    ///
    case v32_0_11 = "32.0.11"

    ///
    /// 33.0.5
    ///
    case v33_0_5 = "33.0.5"

    ///
    /// 34.0.0
    ///
    case v34_0_0 = "34.0.0"

    ///
    /// All server versions the test suite covers.
    ///
    /// During fixture recording the `RAINMAKER_FIXTURE_VERSION` environment variable restricts this to the single version the live container is running, so that a parameterized test only exercises and records the matching version. When the variable is unset (the default, and the case during replay in CI and when the tool enumerates versions) every supported version is returned.
    ///
    public static var allCases: [ServerVersion] {
        let everyVersion: [ServerVersion] = [.v31_0_14, .v32_0_11, .v33_0_5, .v34_0_0]

        guard let only = ProcessInfo.processInfo.environment["RAINMAKER_FIXTURE_VERSION"] else {
            return everyVersion
        }

        return everyVersion.filter { $0.rawValue == only }
    }

    ///
    /// Returns the raw value.
    ///
    public var description: String {
        rawValue
    }

    ///
    /// Returns the raw value.
    ///
    public var debugDescription: String {
        rawValue
    }
}
