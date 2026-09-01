// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import RainmakerTestServerTags
import Testing

///
/// About retrieving the activity stream the server records for the authenticated user.
///
/// The fixtures backing this suite are hand-authored with synthetic, version-independent values and carried forward across versions, because the activities the endpoint returns depend on server state a plain baseline does not reproduce, and because the end of the stream, the previews and an absent activity app cannot be provoked on one. This mirrors ``NotificationsTests``.
///
@Suite("Activity") struct ActivityTests: ServerTesting {
    @Test("Require Credentials", arguments: ServerVersion.allCases)
    func requireCredentials(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(user: nil, password: nil, serverVersion: serverVersion)

        // Credentials are required, so the call fails before any network request is made.
        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.activities(filter: ActivityFilter.all, since: 0, limit: 50, sort: .newestFirst, previews: false, objectType: nil, objectId: nil)
        }

        await #expect(throws: RainmakerError.credentialsRequired) {
            _ = try await server.activityFilters()
        }
    }

    @Test("Fetch", arguments: ServerVersion.allCases)
    func fetch(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let page = try await server.activities(filter: ActivityFilter.all, since: 0, limit: 50, sort: .newestFirst, previews: false, objectType: nil, objectId: nil)

        #expect(page.items.count == 2)

        // The cursors come from the response headers and are what a caller needs to continue paging.
        #expect(page.firstKnown == 3)
        #expect(page.lastGiven == 2)

        // The server order is preserved, newest first.
        #expect(page.items.map(\.id) == [3, 2])

        let file = try #require(page.items.first { $0.id == 3 })
        #expect(file.app == "files")
        #expect(file.type == "file_changed")
        #expect(file.user == "admin")
        #expect(file.affectedUser == "admin")
        #expect(file.subject == "You changed Readme.md")
        #expect(file.message == "")
        #expect(file.objectType == "files")
        #expect(file.objectName == "/Readme.md")
        #expect(file.objects == ["72": "/Readme.md"])
        #expect(file.link == "http://localhost/apps/files/?dir=/")
        #expect(file.icon == "http://localhost/apps/files/img/change.svg")
        #expect(file.creation == Date(timeIntervalSince1970: 1_700_000_000))

        // The identifier of the referenced object arrives as a number here and as a string below, and both end up as a string.
        #expect(file.objectId == "72")

        // Previews are opt-in, so they stay empty until they are requested.
        #expect(file.previews.isEmpty)

        let subjectRich = try #require(file.subjectRich)
        #expect(subjectRich.template == "You changed {file}")
        #expect(subjectRich.parameters.count == 1)

        // Flattening the rich variant has to reproduce what the server rendered into the plain subject.
        #expect(subjectRich.resolved() == file.subject)

        let fileParameter = try #require(subjectRich.parameters["file"])
        #expect(fileParameter.type == "file")
        #expect(fileParameter.id == "72")
        #expect(fileParameter.name == "Readme.md")
        #expect(fileParameter.path == "Readme.md")
        #expect(fileParameter.link == "http://localhost/f/72")

        // Fields of a rich object which are not modelled explicitly stay accessible instead of being dropped.
        #expect(fileParameter.other == ["mimetype": "text/markdown"])

        // The server serializes a rich text without parameters as an empty array rather than as an empty object.
        let messageRich = try #require(file.messageRich)
        #expect(messageRich.template == "")
        #expect(messageRich.parameters.isEmpty)

        let calendar = try #require(page.items.first { $0.id == 2 })
        #expect(calendar.app == "dav")
        #expect(calendar.objectId == "2")
        #expect(calendar.affectedUser == nil)
        #expect(calendar.link == "")
        #expect(calendar.creation == Date(timeIntervalSince1970: 1_699_990_000))

        // Merged activities are about more than one object, which only this map reports in full.
        #expect(calendar.objects == ["2": "", "3": "Sprint review"])

        let calendarRich = try #require(calendar.subjectRich)
        #expect(calendarRich.resolved() == calendar.subject)

        // A parameter may be sent without the template ever referencing it, which must not affect flattening.
        #expect(calendarRich.parameters.count == 3)
        #expect(calendarRich.parameters["actor"]?.type == "user")

        // A rich object of a type which has neither is decoded without a path or a link rather than with empty ones.
        let calendarParameter = try #require(calendarRich.parameters["calendar"])
        #expect(calendarParameter.name == "Personal")
        #expect(calendarParameter.path == nil)
        #expect(calendarParameter.link == nil)
        #expect(calendarParameter.other.isEmpty)
    }

    @Test("Fetch With Previews", arguments: ServerVersion.allCases)
    func fetchWithPreviews(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let page = try await server.activities(filter: ActivityFilter.all, since: 0, limit: 50, sort: .newestFirst, previews: true, objectType: nil, objectId: nil)

        let item = try #require(page.items.first)
        #expect(item.previews.count == 1)

        let preview = try #require(item.previews.first)
        #expect(preview.fileId == 72)
        #expect(preview.filename == "Readme.md")
        #expect(preview.filePath == "/admin/files/Readme.md")
        #expect(preview.mimeType == "text/markdown")
        #expect(preview.isMimeTypeIcon == false)
        #expect(preview.view == "files")
        #expect(preview.link == "http://localhost/f/72")
        #expect(preview.source.hasPrefix("http://localhost/core/preview"))
    }

    @Test("Fetch Empty", arguments: ServerVersion.allCases)
    func fetchEmpty(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let page = try await server.activities(filter: ActivityFilter.all, since: 1, limit: 50, sort: .newestFirst, previews: false, objectType: nil, objectId: nil)

        // Reaching the end of the stream is a not modified response with an empty body, which is a page without items rather than an error.
        #expect(page.items.isEmpty)

        // The newest known identifier is still reported so a caller can tell whether anything new happened.
        #expect(page.firstKnown == 3)

        // Without any activity given there is nothing to continue after.
        #expect(page.lastGiven == nil)
    }

    @Test("Fetch With Disabled App", arguments: ServerVersion.allCases)
    func fetchWithDisabledApp(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // When the activity app is not installed or enabled, the endpoint does not exist and a not found error surfaces.
        await #expect(throws: RainmakerError.notFound) {
            _ = try await server.activities(filter: ActivityFilter.all, since: 0, limit: 50, sort: .newestFirst, previews: false, objectType: nil, objectId: nil)
        }
    }

    @Test("Fetch Filtered By Object", arguments: ServerVersion.allCases)
    func fetchFilteredByObject(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)

        // Naming an object selects the object filter, which is why this is served from a different path than the unfiltered stream.
        let page = try await server.activities(filter: ActivityFilter.all, since: 0, limit: 50, sort: .newestFirst, previews: false, objectType: "files", objectId: "72")

        #expect(page.items.count == 1)
        #expect(page.items.first?.id == 1)
        #expect(page.items.first?.objectId == "72")
        #expect(page.lastGiven == 1)
    }

    @Test("Fetch Filters", arguments: ServerVersion.allCases)
    func fetchFilters(_ serverVersion: ServerVersion) async throws {
        let server = try makeServer(serverVersion: serverVersion)
        let filters = try await server.activityFilters()

        #expect(filters.count == 4)

        // The server order is preserved, which is the order it suggests presenting them in.
        #expect(filters.map(\.id) == [ActivityFilter.all, ActivityFilter.own, ActivityFilter.others, "files"])

        let all = try #require(filters.first)
        #expect(all.name == "All activity")
        #expect(all.priority == 0)
        #expect(all.icon == "http://localhost/apps/activity/img/activity-dark.svg")

        // Beyond the well-known filters a server contributes further, app-provided ones which only this call can discover.
        #expect(filters.last?.id == "files")
        #expect(filters.last?.priority == 30)
    }
}
