// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `GET /ocs/v2.php/apps/collectives/api/v1.0/collectives/{collectiveId}/pages`.
///
/// This is a data transfer object covering the OCS envelope. Like ``CollectivesResponse`` the endpoint wraps its array in an object rather than sending it as `data` itself, which is what the nested ``OCS/Data`` mirrors. The fixed-shape entries are decoded directly into public ``CollectivePage`` values for external callers.
///
struct PagesResponse: Decodable {
    struct OCS: Decodable {
        struct Meta: Decodable {
            let status: String
            let statuscode: Int
            let message: String?
        }

        struct Data: Decodable {
            let pages: [CollectivePage]
        }

        let meta: Meta
        let data: Data
    }

    let ocs: OCS
}
