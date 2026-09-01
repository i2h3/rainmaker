// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's activity capability, advertised when the activity app is installed and enabled.
///
/// On Nextcloud, the activity stream is provided by the bundled "Activity" app (`activity`). When that app is available the server advertises this object under the `activity` key, which is why ``key`` is `"activity"`. Its mere presence is the signal a client needs before calling ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)``: check it with `try await capabilities().contains(Activity.self)`.
///
/// The object is only advertised to authenticated clients; an anonymous capabilities request does not contain it.
/// All fields are kept optional so that a server which omits one of them still decodes successfully.
///
public struct Activity: Capability {
    public static let key = "activity"

    ///
    /// The optional features of the version 2 API the server supports, e.g. `["filters", "filters-api", "previews", "rich-strings"]`.
    ///
    /// The `"filters-api"` entry backs ``Server/activityFilters()``, `"previews"` backs the `previews` argument of ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` and `"rich-strings"` backs ``ActivityItem/subjectRich``.
    ///
    public let apiV2: [String]?

    private enum CodingKeys: String, CodingKey {
        case apiV2 = "apiv2"
    }
}
