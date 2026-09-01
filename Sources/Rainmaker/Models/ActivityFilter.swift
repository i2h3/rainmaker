// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A named subset of the activity stream the server offers to narrow it down to.
///
/// Filters are contributed by the server and its installed apps rather than being a fixed list, which is why ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` takes a plain string and why the available ones are discovered at runtime through ``Server/activityFilters()``. Beyond the four well-known ones declared here, a server typically offers one per app recording activities, e.g. `"files"`, `"calendar"` or `"comments"`.
///
/// Whether the server supports discovering them is advertised under the ``Activity`` capability's `"filters-api"` entry.
///
public struct ActivityFilter: Model, Identifiable, Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    ///
    /// Every activity, which is what the server falls back to when no filter is given.
    ///
    public static let all = "all"

    ///
    /// Only activities the authenticated user caused themselves.
    ///
    public static let own = "self"

    ///
    /// Only activities somebody other than the authenticated user caused.
    ///
    public static let others = "by"

    ///
    /// Only activities about one specific object, which is the filter the `objectType` and `objectId` arguments of ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` require.
    ///
    /// Passing that pair selects this filter automatically, so it rarely has to be named explicitly.
    ///
    public static let object = "filter"

    ///
    /// The identifier of the filter, which is what ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` expects as its `filter` argument.
    ///
    public let id: String

    ///
    /// The human-readable name of the filter, rendered by the server in the account's language.
    ///
    public let name: String

    ///
    /// The address of the filter icon. Empty when the filter carries no icon.
    ///
    /// This is kept as a string rather than a `URL` because the server may return an empty value.
    ///
    public let icon: String

    ///
    /// The order in which the server suggests presenting the filters, ascending.
    ///
    public let priority: Int

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a filter.
    ///
    public var description: String {
        name
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a filter.
    ///
    public var debugDescription: String {
        "\(id) (\(priority)): \(name)"
    }
}
