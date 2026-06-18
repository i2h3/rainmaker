// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This is the JSON response as returned by the server for `GET /ocs/v2.php/cloud/capabilities`.
///
/// This is a data transfer object covering only the parts of the OCS envelope with a known, stable shape.
/// The open-ended `capabilities` object is intentionally not modelled here; it is sliced out as raw bytes and wrapped in a ``CapabilitySet`` for external callers.
///
struct CapabilitiesResponse: Decodable {
    struct OCS: Decodable {
        struct Meta: Decodable {
            let status: String
            let statuscode: Int
            let message: String?
        }

        struct Data: Decodable {
            let version: Version
        }

        let meta: Meta
        let data: Data
    }

    let ocs: OCS
}
