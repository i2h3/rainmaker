// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A single entry of the activity stream the server keeps for the authenticated user.
///
/// Activities are what the server records about everything happening in an account: files being created, changed and shared, calendar events being scheduled, security relevant events and whatever else an installed app contributes. They are listed through ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)``, and whether the app which provides them is available at all can be checked in advance via the ``Activity`` capability.
///
/// Every entry carries its text twice. ``subject`` and ``message`` are the flat sentences the server already rendered, which is all a client needs to display an activity as plain text. ``subjectRich`` and ``messageRich`` are their interpolatable counterparts, which let a client render the referenced files, users and tags as interactive elements instead.
///
/// An entry can be about more than one object because the server merges related activities: ``objectType`` and ``objectId`` then identify the primary object while ``objects`` lists all of them.
///
public struct ActivityItem: Model, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, Decodable {
    ///
    /// The server-assigned identifier of the activity, unique per user and increasing over time.
    ///
    /// This corresponds to the server's `activity_id`. It doubles as the pagination cursor: it is what ``ActivityPage/lastGiven`` reports and what the `since` parameter of ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` expects.
    ///
    public let id: Int

    ///
    /// The identifier of the app which recorded the activity, e.g. `"files"`.
    ///
    /// This is also what the app-provided filters returned by ``Server/activityFilters()`` narrow the stream down to.
    ///
    public let app: String

    ///
    /// The kind of activity within its app, e.g. `"file_created"` or `"file_changed"`.
    ///
    public let type: String

    ///
    /// The name of the user who caused the activity.
    ///
    public let user: String

    ///
    /// The name of the user whose stream the activity was recorded in. `nil` when the server does not report it.
    ///
    /// This differs from ``user`` when somebody else acted on the account's content, which is what the `"self"` and `"by"` filters distinguish.
    ///
    public let affectedUser: String?

    ///
    /// The moment the activity happened on the server.
    ///
    /// This corresponds to the server's `datetime` field, an ISO 8601 timestamp, and is named to match ``NotificationItem/creation``.
    ///
    public let creation: Date

    ///
    /// The human-readable sentence describing the activity, e.g. `"You changed Readme.md"`.
    ///
    /// The server renders this in the account's language. Its interpolatable counterpart is ``subjectRich``.
    ///
    public let subject: String

    ///
    /// The interpolatable variant of ``subject``. `nil` when the server did not send one.
    ///
    /// Calling ``ActivityRichText/resolved()`` on this reproduces ``subject``.
    ///
    public let subjectRich: ActivityRichText?

    ///
    /// The human-readable body of the activity. Empty when the activity carries no body, which is the common case.
    ///
    public let message: String

    ///
    /// The interpolatable variant of ``message``. `nil` when the server did not send one.
    ///
    /// Its ``ActivityRichText/template`` is empty whenever ``message`` is, which is the common case.
    ///
    public let messageRich: ActivityRichText?

    ///
    /// The type of the object the activity is about, e.g. `"files"`.
    ///
    /// Together with ``objectId`` this identifies the object, and both together are what the `objectType` and `objectId` parameters of ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)`` expect in order to narrow the stream down to a single object.
    ///
    public let objectType: String

    ///
    /// The identifier of the object the activity is about.
    ///
    /// This is a string even though the server usually sends a number, because the server documents the field as either.
    ///
    public let objectId: String

    ///
    /// The name of the object the activity is about, e.g. `"/Readme.md"`. Empty when the server does not report one.
    ///
    public let objectName: String

    ///
    /// Every object the activity is about, keyed by identifier and valued by name.
    ///
    /// This holds more than one entry when the server merged several related activities into this one, in which case ``objectId`` and ``objectName`` only identify the primary object.
    ///
    public let objects: [String: String]

    ///
    /// The address a client should open when the activity is activated. Empty when the activity is not actionable through a link.
    ///
    /// This is kept as a string rather than a `URL` because the server may return an empty value.
    ///
    public let link: String

    ///
    /// The address of the activity icon. Empty when the activity carries no icon.
    ///
    /// This is kept as a string rather than a `URL` because the server may return an empty value.
    ///
    public let icon: String

    ///
    /// The thumbnails the server offers for the files this activity refers to.
    ///
    /// This is empty unless previews were requested through the `previews` parameter of ``Server/activities(filter:since:limit:sort:previews:objectType:objectId:)``, and stays empty for activities which reference no files.
    ///
    public let previews: [ActivityPreview]

    private enum CodingKeys: String, CodingKey {
        case id = "activity_id"
        case app
        case type
        case user
        case affectedUser = "affecteduser"
        case creation = "datetime"
        case subject
        case subjectRich = "subject_rich"
        case message
        case messageRich = "message_rich"
        case objectType = "object_type"
        case objectId = "object_id"
        case objectName = "object_name"
        case objects
        case link
        case icon
        case previews
    }

    // MARK: - Encodable

    ///
    /// The keys an activity is encoded under, which are the property names rather than the names the server sends.
    ///
    /// Encoding deliberately does not reuse ``CodingKeys``: those exist to read the server's payload and carry its naming, which would leak back out into anything this library encodes. Keeping the two apart is what makes the encoded form match the model a Swift caller sees, including where a property was renamed for clarity such as ``creation`` over the server's `datetime`.
    ///
    private enum EncodingKeys: String, CodingKey {
        case id
        case app
        case type
        case user
        case affectedUser
        case creation
        case subject
        case subjectRich
        case message
        case messageRich
        case objectType
        case objectId
        case objectName
        case objects
        case link
        case icon
        case previews
    }

    ///
    /// Encode an activity under its property names, so that the encoded form mirrors this type rather than the server's payload.
    ///
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(app, forKey: .app)
        try container.encode(type, forKey: .type)
        try container.encode(user, forKey: .user)
        try container.encodeIfPresent(affectedUser, forKey: .affectedUser)
        try container.encode(creation, forKey: .creation)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(subjectRich, forKey: .subjectRich)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(messageRich, forKey: .messageRich)
        try container.encode(objectType, forKey: .objectType)
        try container.encode(objectId, forKey: .objectId)
        try container.encode(objectName, forKey: .objectName)
        try container.encode(objects, forKey: .objects)
        try container.encode(link, forKey: .link)
        try container.encode(icon, forKey: .icon)
        try container.encode(previews, forKey: .previews)
    }

    // MARK: - Decodable

    ///
    /// Decode an activity, absorbing the two shapes the server is inconsistent about.
    ///
    /// The identifier of the referenced object arrives as a number in practice but is documented as either a number or a string, and an empty object map is serialized as an empty array rather than as an empty object. Fields the server omits for some activities fall back to their empty value so that an entry never fails to decode over a detail a client does not need.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        app = try container.decodeIfPresent(String.self, forKey: .app) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        user = try container.decodeIfPresent(String.self, forKey: .user) ?? ""
        affectedUser = try container.decodeIfPresent(String.self, forKey: .affectedUser)
        creation = try container.decode(Date.self, forKey: .creation)
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        subjectRich = try container.decodeIfPresent(ActivityRichText.self, forKey: .subjectRich)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        messageRich = try container.decodeIfPresent(ActivityRichText.self, forKey: .messageRich)
        objectType = try container.decodeIfPresent(String.self, forKey: .objectType) ?? ""

        if let numericObjectId = try? container.decode(Int.self, forKey: .objectId) {
            objectId = String(numericObjectId)
        } else {
            objectId = try container.decodeIfPresent(String.self, forKey: .objectId) ?? ""
        }

        objectName = try container.decodeIfPresent(String.self, forKey: .objectName) ?? ""
        objects = (try? container.decode([String: String].self, forKey: .objects)) ?? [:]
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        previews = try container.decodeIfPresent([ActivityPreview].self, forKey: .previews) ?? []
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of an activity.
    ///
    public var description: String {
        subject
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of an activity.
    ///
    public var debugDescription: String {
        "#\(id) (\(app)/\(type)): \(subject)"
    }
}
