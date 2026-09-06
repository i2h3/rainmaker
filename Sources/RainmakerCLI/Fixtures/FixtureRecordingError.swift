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

        ///
        /// An app a suite's fixtures depend on could not be installed into the deployed container.
        ///
        case appInstallationFailed(String)

        ///
        /// Something the recording depends on never started answering.
        ///
        case serverNotReady(subject: String, reason: String)

        var description: String {
            switch self {
                case .verificationFailed:
                    "The replay-verify pass failed: the recorded fixtures do not reproduce passing tests without a server. Inspect the test output above and, for any failing test, add its precondition in FixtureProvisioner.applyPrecondition(forTest:)."
                case let .serverNotReady(subject: subject, reason: reason):
                    "Gave up waiting for \(subject): \(reason)."
                case let .appInstallationFailed(app):
                    "The \"\(app)\" app could not be installed into the container. It is fetched from the Nextcloud app store, so check that the store is reachable and that it offers a release compatible with the server version being recorded."
            }
        }
    }
#endif
