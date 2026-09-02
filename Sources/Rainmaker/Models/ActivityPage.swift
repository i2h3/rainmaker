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
/// Checking whether anything new happened instead works the other way around, by remembering the identifier of the newest activity seen and issuing a fresh request without a cursor: the first entry of the resulting page, or its ``firstKnown``, is what to compare against. This pairs with ``ServerEvent/activities``, which announces that something changed without saying what.
///
public struct ActivityPage: Model {
    ///
    /// The activities in this page, in the order returned by the server.
    ///
    /// With the default sort order this is newest first. An empty array means there is nothing more to read, which the server signals either with a `304 Not Modified` response at the end of the stream or with a `204 No Content` response when the account has every activity type switched off.
    ///
    public let items: [ActivityItem]

    ///
    /// The identifier of the newest activity the server knows about. `nil` whenever the server did not report it, which is the common case for every page but the first.
    ///
    /// This corresponds to the server's `X-Activity-First-Known` header, which the server only sends when it did not recognize the requested cursor, so above all when a request carries no `since` argument at all. A page fetched by passing a previous page's ``lastGiven`` therefore usually leaves this `nil` even though it has activities. It is emitted for an empty page too, as long as the cursor was absent or unrecognized.
    ///
    /// Because of that this is not a page-independent newest-identifier field to be read off any response. Use it to learn the newest identifier from a request made without a cursor, and do not treat `nil` as a statement about the stream.
    ///
    public let firstKnown: Int?

    ///
    /// The identifier of the last activity in this page, to be passed as the `since` argument to retrieve the following one. `nil` when the server did not report it, which is the case for an empty page.
    ///
    /// This corresponds to the server's `X-Activity-Last-Given` header.
    ///
    public let lastGiven: Int?
}
