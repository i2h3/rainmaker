// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The direction in which ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` walks the activity stream.
///
/// The raw values are the tokens the server expects for its `sort` parameter.
///
public enum ActivitySort: String, Sendable, CaseIterable {
    ///
    /// Return the newest activities first and page backwards into the past, which is the server's default.
    ///
    case newestFirst = "desc"

    ///
    /// Return the oldest activities first and page forwards towards the present.
    ///
    case oldestFirst = "asc"
}
