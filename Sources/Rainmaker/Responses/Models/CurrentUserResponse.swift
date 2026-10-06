// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `GET /ocs/v2.php/cloud/user`.
///
/// This is a data transfer object covering the OCS envelope and the two fields of the account details ``Server/currentUser()`` maps onto the public ``User``.
/// The server sends many more details of the account, such as its quota, its groups and when it last logged in, which are deliberately not decoded, so that a change to any of them cannot break the lookup.
///
struct CurrentUserResponse: Decodable {
    ///
    /// The OCS envelope wrapping the status of the request and the account details.
    ///
    struct OCS: Decodable {
        ///
        /// The status of the OCS request, which ``Server/currentUser()`` checks before it reads ``OCS/data``.
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
        /// The details of the account which ``Server/currentUser()`` needs.
        ///
        struct Data: Decodable {
            ///
            /// The identifier the server keys the account by, which becomes ``User/id``.
            ///
            let id: String

            ///
            /// The display name of the account, which becomes ``User/displayName`` and which the server falls back to the identifier for.
            ///
            let displayname: String
        }

        ///
        /// The status of the request.
        ///
        let meta: Meta

        ///
        /// The details of the account.
        ///
        let data: Data
    }

    ///
    /// The OCS envelope, which is the only top-level key of the response.
    ///
    let ocs: OCS
}
