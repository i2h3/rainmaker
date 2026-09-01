// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `GET /ocs/v2.php/apps/activity/api/v2/activity/{filter}`.
///
/// This is a data transfer object covering the OCS envelope. The fixed-shape `data` array is decoded directly into public ``ActivityItem`` values for external callers, which are then paired with the cursors from the response headers into an ``ActivityPage``.
///
struct ActivityResponse: Decodable {
    struct OCS: Decodable {
        struct Meta: Decodable {
            let status: String
            let statuscode: Int
            let message: String?
        }

        let meta: Meta
        let data: [ActivityItem]
    }

    let ocs: OCS
}
