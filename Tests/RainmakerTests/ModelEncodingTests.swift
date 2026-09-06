// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// About how the public data models encode themselves.
///
/// The models read the server's payload, whose field names are snake-cased and occasionally differ from what the model calls them. Those names must not leak back out when a model is encoded again, because the encoded form is part of what this library offers downstream and is what the command line interface prints. This suite guards that separation, which is easy to lose by reusing one set of coding keys for both directions.
///
/// No fixtures or network are involved: every model is decoded from a literal payload and encoded straight back.
///
@Suite("Model Encoding") struct ModelEncodingTests {
    ///
    /// Decode a model from a literal payload and return the keys of its encoded representation.
    ///
    private func encodedKeys<Value: Decodable & Encodable>(of _: Value.Type, from payload: String) throws -> Set<String> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Value.self, from: Data(payload.utf8))

        let data = try JSONEncoder().encode(value)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        return Set(object.keys)
    }

    @Test("Activity Item Encodes Under Its Property Names")
    func activityItem() throws {
        let payload = """
        {"activity_id":3,"app":"files","type":"file_changed","user":"admin","affecteduser":"admin","subject":"You changed Readme.md","subject_rich":["You changed {file}",{"file":{"type":"file","id":"72","name":"Readme.md","path":"Readme.md"}}],"message":"","message_rich":["",[]],"object_type":"files","object_id":72,"object_name":"/Readme.md","objects":{"72":"/Readme.md"},"link":"","icon":"","datetime":"2023-11-14T22:13:20+00:00"}
        """

        let keys = try encodedKeys(of: ActivityItem.self, from: payload)

        // The names the server sends must not survive a round trip.
        #expect(keys.isDisjoint(with: ["activity_id", "affecteduser", "datetime", "subject_rich", "message_rich", "object_type", "object_id", "object_name"]))

        #expect(keys == ["id", "app", "type", "user", "affectedUser", "creation", "subject", "subjectRich", "message", "messageRich", "objectType", "objectId", "objectName", "objects", "link", "icon", "previews"])
    }

    @Test("Notification Item Encodes Under Its Property Names")
    func notificationItem() throws {
        let payload = """
        {"notification_id":1,"app":"admin_notifications","user":"admin","datetime":"2023-11-14T22:13:20+00:00","object_type":"admin_notifications","object_id":"1","subject":"Hello, world!","message":"","link":"","icon":""}
        """

        let keys = try encodedKeys(of: NotificationItem.self, from: payload)

        #expect(keys.isDisjoint(with: ["notification_id", "datetime", "object_type", "object_id"]))
        #expect(keys == ["id", "app", "user", "creation", "objectType", "objectId", "subject", "message", "link", "icon"])
    }

    @Test("Note Encodes Under Its Property Names")
    func note() throws {
        let payload = """
        {"id":76,"etag":"be284e00488c61c101ee28309d235e0b","readonly":false,"modified":1376753464,"title":"New note","category":"sub-directory","content":"New note","favorite":false}
        """

        let keys = try encodedKeys(of: Note.self, from: payload)

        #expect(keys.isDisjoint(with: ["etag", "readonly", "favorite", "modified"]))
        #expect(keys == ["id", "entityTag", "isReadOnly", "title", "category", "content", "isFavorite", "modification"])
    }

    @Test("Note Settings Encode Under Their Property Names")
    func notesSettings() throws {
        let payload = """
        {"notesPath":"Notizen","fileSuffix":".md","noteMode":"rich"}
        """

        let keys = try encodedKeys(of: NotesSettings.self, from: payload)

        // The server already names these the way this library does, so the two key sets coincide rather than needing a translation. The undocumented field must not survive.
        #expect(keys == ["notesPath", "fileSuffix"])
    }

    @Test("Navigation Item Encodes Under Its Property Names")
    func navigationItem() throws {
        let payload = """
        {"id":"files","order":0,"href":"/apps/files/","icon":"/apps/files/img/app.svg","type":"link","name":"Files","app":"files","active":false,"unread":0,"classes":"","default":true}
        """

        let keys = try encodedKeys(of: NavigationItem.self, from: payload)

        #expect(keys.isDisjoint(with: ["active", "default"]))
        #expect(keys == ["id", "order", "href", "icon", "type", "name", "app", "isActive", "unread", "classes", "isDefault"])
    }

    @Test("Nested Activity Models Encode Under Their Property Names")
    func nestedActivityModels() throws {
        let payload = """
        {"activity_id":3,"app":"files","type":"file_created","user":"admin","subject":"You created Readme.md","subject_rich":["You created {file}",{"file":{"type":"file","id":"72","name":"Readme.md","path":"Readme.md","link":"http://localhost/f/72","mimetype":"text/markdown"}}],"message":"","message_rich":["",[]],"object_type":"files","object_id":72,"object_name":"/Readme.md","objects":{"72":"/Readme.md"},"link":"","icon":"","datetime":"2023-11-14T22:13:20+00:00","previews":[{"link":"http://localhost/f/72","source":"http://localhost/core/preview","mimeType":"text/markdown","isMimeTypeIcon":false,"fileId":72,"view":"files","filename":"Readme.md","filePath":"/admin/files/Readme.md"}]}
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(ActivityItem.self, from: Data(payload.utf8))

        let data = try JSONEncoder().encode(item)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // The whole document has to read consistently, so the nested models must not fall back to the server's naming either.
        let richText = try #require(object["subjectRich"] as? [String: Any])
        #expect(Set(richText.keys) == ["template", "parameters"])

        let parameters = try #require(richText["parameters"] as? [String: Any])
        let richObject = try #require(parameters["file"] as? [String: Any])
        #expect(Set(richObject.keys) == ["type", "id", "name", "path", "link", "other"])

        let preview = try #require((object["previews"] as? [[String: Any]])?.first)
        #expect(Set(preview.keys) == ["link", "source", "mimeType", "isMimeTypeIcon", "fileId", "view", "filename", "filePath"])
    }
}
