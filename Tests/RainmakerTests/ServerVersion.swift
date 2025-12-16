// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Server releases to test against.
///
public enum ServerVersion: String, CaseIterable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    ///
    /// 31.0.12
    ///
    case v31_0_12 = "31.0.12"

    ///
    /// 32.0.3
    ///
    case v32_0_3 = "32.0.3"

    ///
    /// Returns the raw value.
    ///
    public var description: String {
        self.rawValue
    }

    ///
    /// Returns the raw value.
    ///
    public var debugDescription: String {
        self.rawValue
    }
}
