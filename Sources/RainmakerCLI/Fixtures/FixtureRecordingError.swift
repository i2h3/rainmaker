// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

#if os(macOS)
    import Foundation

    ///
    /// Errors raised while orchestrating fixture recording.
    ///
    enum FixtureRecordingError: Error, CustomStringConvertible {
        ///
        /// The replay-verify pass failed, meaning the recorded fixtures do not reproduce passing tests without a live server.
        ///
        case verificationFailed

        var description: String {
            switch self {
                case .verificationFailed:
                    "The replay-verify pass failed: the recorded fixtures do not reproduce passing tests without a server. Inspect the test output above and, for any failing test, add its precondition in FixtureProvisioner.applyPrecondition(forTest:)."
            }
        }
    }
#endif
