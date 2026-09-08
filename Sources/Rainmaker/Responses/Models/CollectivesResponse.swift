// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `GET /ocs/v2.php/apps/collectives/api/v1.0/collectives`.
///
/// This is a data transfer object covering the OCS envelope. Unlike the notifications response, whose `data` is the array itself, this endpoint wraps its array in an object, which is what the nested ``OCS/Data`` mirrors. The fixed-shape entries are decoded directly into public ``Collective`` values for external callers.
///
struct CollectivesResponse: Decodable {
    struct OCS: Decodable {
        struct Meta: Decodable {
            let status: String
            let statuscode: Int
            let message: String?
        }

        struct Data: Decodable {
            let collectives: [Collective]
        }

        let meta: Meta
        let data: Data
    }

    let ocs: OCS
}
