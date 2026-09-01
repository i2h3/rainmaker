// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One page of the activity stream together with the cursors needed to request the next one.
///
/// The server never returns the whole stream at once, so ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` returns a page and leaves paging to the caller. Walking the stream backwards into the past means calling it again with ``lastGiven`` as the `since` argument until a page comes back with no ``items``:
///
/// ```swift
/// var page = try await server.activities()
/// var activities = page.items
///
/// while let cursor = page.lastGiven, page.items.isEmpty == false {
///     page = try await server.activities(since: cursor)
///     activities.append(contentsOf: page.items)
/// }
/// ```
///
/// Checking whether anything new happened instead works the other way around: keep ``firstKnown`` from the last page fetched and compare it against the ``firstKnown`` of a fresh request. This pairs with ``ServerEvent/activities``, which announces that something changed without saying what.
///
public struct ActivityPage: Model {
    ///
    /// The activities in this page, in the order returned by the server.
    ///
    /// With the default sort order this is newest first. An empty array means the end of the stream has been reached, which the server signals with a `304 Not Modified` response.
    ///
    public let items: [ActivityItem]

    ///
    /// The identifier of the newest activity the server knows about, regardless of which page was requested. `nil` when the server did not report it.
    ///
    /// This corresponds to the server's `X-Activity-First-Known` header and is reported even for an empty page, which makes it the value to remember in order to detect later whether anything new happened.
    ///
    public let firstKnown: Int?

    ///
    /// The identifier of the last activity in this page, to be passed as the `since` argument to retrieve the following one. `nil` when the server did not report it, which is the case for an empty page.
    ///
    /// This corresponds to the server's `X-Activity-Last-Given` header.
    ///
    public let lastGiven: Int?
}
