// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `GET /ocs/v2.php/core/autocomplete/get`.
///
/// This is a data transfer object covering the OCS envelope and the two fields of every match ``Server/searchUsers(_:)`` maps onto the public ``User``.
/// The server sends more about a match, such as its icon, its user status and the kind of account it is, which are deliberately not decoded, so that a change to any of them cannot break the search.
///
struct UserSearchResponse: Decodable {
    ///
    /// The OCS envelope wrapping the status of the request and the matches.
    ///
    struct OCS: Decodable {
        ///
        /// The status of the OCS request, which ``Server/searchUsers(_:)`` checks before it reads ``OCS/data``.
        ///
        struct Meta: Decodable {
            ///
            /// The textual status, which is `"ok"` for a successful request.
            ///
            let status: String

            ///
            /// The numeric OCS status code, which is reported in the error when ``status`` is not `"ok"`.
            ///
            let statuscode: Int

            ///
            /// The optional message explaining a failure, which is reported in the error when ``status`` is not `"ok"`.
            ///
            let message: String?
        }

        ///
        /// A single user matching the search.
        ///
        struct Match: Decodable {
            ///
            /// The identifier the server keys the account by, which becomes ``User/id``.
            ///
            let id: String

            ///
            /// The name the server presents the account under, which becomes ``User/displayName``.
            ///
            let label: String
        }

        ///
        /// The status of the request.
        ///
        let meta: Meta

        ///
        /// The matching users, exact matches first.
        ///
        let data: [Match]
    }

    ///
    /// The OCS envelope.
    ///
    let ocs: OCS
}
