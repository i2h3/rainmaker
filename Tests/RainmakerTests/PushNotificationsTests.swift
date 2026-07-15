// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// Decoding of the `notify_push` capability out of a raw capabilities object.
///
@Suite("Push Notifications Capability") struct PushNotificationsTests {
    ///
    /// A version value the tests pair with a raw capabilities object to build a ``CapabilitySet``.
    ///
    private var version: Version {
        Version(major: 31, minor: 0, micro: 0, string: "31.0.0", edition: "", extendedSupport: false)
    }

    @Test("Present")
    func present() throws {
        let raw = Data(#"{"notify_push":{"type":["files","activities","notifications"],"endpoints":{"websocket":"wss://cloud.example.com/push/ws","pre_auth":"https://cloud.example.com/apps/notify_push/pre_auth"}}}"#.utf8)
        let capabilities = CapabilitySet(version: version, raw: raw)

        #expect(capabilities.contains(PushNotifications.self))

        let push = try #require(try capabilities.get(PushNotifications.self))
        #expect(push.type == ["files", "activities", "notifications"])
        #expect(push.endpoints?.websocket == URL(string: "wss://cloud.example.com/push/ws"))
        #expect(push.endpoints?.preAuth == URL(string: "https://cloud.example.com/apps/notify_push/pre_auth"))
    }

    @Test("Absent")
    func absent() throws {
        let raw = Data(#"{"theming":{"name":"Nextcloud"}}"#.utf8)
        let capabilities = CapabilitySet(version: version, raw: raw)

        #expect(capabilities.contains(PushNotifications.self) == false)
        #expect(try capabilities.get(PushNotifications.self) == nil)
    }

    @Test("Missing Endpoint Decodes")
    func missingEndpoint() throws {
        // A server may advertise the key without a configured backend; it must still decode, with a nil endpoint.
        let raw = Data(#"{"notify_push":{"type":["notifications"]}}"#.utf8)
        let capabilities = CapabilitySet(version: version, raw: raw)

        let push = try #require(try capabilities.get(PushNotifications.self))
        #expect(push.type == ["notifications"])
        #expect(push.endpoints == nil)
    }
}
