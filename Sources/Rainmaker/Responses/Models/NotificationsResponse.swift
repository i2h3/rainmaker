// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `GET /ocs/v2.php/apps/notifications/api/v2/notifications`.
///
/// This is a data transfer object covering the OCS envelope. The fixed-shape `data` array is decoded directly into public ``NotificationItem`` values for external callers.
///
struct NotificationsResponse: Decodable {
    struct OCS: Decodable {
        struct Meta: Decodable {
            let status: String
            let statuscode: Int
            let message: String?
        }

        let meta: Meta
        let data: [NotificationItem]
    }

    let ocs: OCS
}
