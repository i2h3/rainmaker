// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
@testable import Rainmaker
import Testing

///
/// The pure mapping and selection logic behind ``Serving/events(_:)``: frame decoding, the endpoint security gate, and transport selection from capabilities.
///
@Suite("Server Event Mapping") struct ServerEventMappingTests {
    private let allSubjects = Set(ServerSubject.allCases)

    @Test("Frame Mapping")
    func frameMapping() {
        #expect(PushNotificationsConnection.event(forFrame: "notify_notification", subjects: allSubjects) == .notifications)
        #expect(PushNotificationsConnection.event(forFrame: "notify_activity", subjects: allSubjects) == .activities)
        #expect(PushNotificationsConnection.event(forFrame: "notify_file", subjects: allSubjects) == .files(ids: nil))
        #expect(PushNotificationsConnection.event(forFrame: "notify_file_id [1,2,3]", subjects: allSubjects) == .files(ids: [1, 2, 3]))
    }

    @Test("Unrequested Subjects Are Dropped")
    func unrequestedSubjectsDropped() {
        let onlyNotifications: Set<ServerSubject> = [.notifications]

        #expect(PushNotificationsConnection.event(forFrame: "notify_notification", subjects: onlyNotifications) == .notifications)
        #expect(PushNotificationsConnection.event(forFrame: "notify_file", subjects: onlyNotifications) == nil)
        #expect(PushNotificationsConnection.event(forFrame: "notify_activity", subjects: onlyNotifications) == nil)
    }

    @Test("Custom And Ignored Frames")
    func customAndIgnoredFrames() {
        #expect(PushNotificationsConnection.event(forFrame: "authenticated", subjects: allSubjects) == nil)
        #expect(PushNotificationsConnection.event(forFrame: "", subjects: allSubjects) == nil)
        #expect(PushNotificationsConnection.event(forFrame: "custom_event", subjects: allSubjects) == .custom(type: "custom_event", body: nil))
        #expect(PushNotificationsConnection.event(forFrame: #"custom_event {"a":1}"#, subjects: allSubjects) == .custom(type: "custom_event", body: #"{"a":1}"#))
    }

    @Test("Malformed File Ids Fall Back")
    func malformedFileIdsFallBack() {
        // A non-array payload cannot decode to identifiers, so it degrades to a plain files hint rather than being dropped.
        #expect(PushNotificationsConnection.event(forFrame: "notify_file_id not-json", subjects: allSubjects) == .files(ids: nil))
    }

    @Test("Endpoint Security Gate")
    func endpointSecurityGate() throws {
        let httpsAccount = try #require(URL(string: "https://cloud.example.com"))
        let httpAccount = try #require(URL(string: "http://localhost"))

        #expect(try ServerEventCoordinator.isAcceptable(endpoint: #require(URL(string: "wss://cloud.example.com/push/ws")), accountAddress: httpsAccount))
        #expect(try ServerEventCoordinator.isAcceptable(endpoint: #require(URL(string: "ws://cloud.example.com/push/ws")), accountAddress: httpsAccount) == false)
        #expect(try ServerEventCoordinator.isAcceptable(endpoint: #require(URL(string: "ws://localhost/push/ws")), accountAddress: httpAccount))
        #expect(try ServerEventCoordinator.isAcceptable(endpoint: #require(URL(string: "https://cloud.example.com/push/ws")), accountAddress: httpsAccount) == false)
    }

    @Test("Push Target Selection")
    func pushTargetSelection() throws {
        let account = try #require(URL(string: "https://cloud.example.com"))
        let version = Version(major: 31, minor: 0, micro: 0, string: "31.0.0", edition: "", extendedSupport: false)

        // Requested subjects are intersected with the advertised type.
        let raw = Data(#"{"notify_push":{"type":["files","notifications"],"endpoints":{"websocket":"wss://cloud.example.com/push/ws"}}}"#.utf8)
        let target = try #require(ServerEventCoordinator.pushTarget(from: CapabilitySet(version: version, raw: raw), requested: [.notifications, .activities], accountAddress: account))
        #expect(target.endpoint == URL(string: "wss://cloud.example.com/push/ws"))
        #expect(target.subjects == [.notifications])

        // No overlap between requested and advertised means no push target.
        #expect(ServerEventCoordinator.pushTarget(from: CapabilitySet(version: version, raw: raw), requested: [.activities], accountAddress: account) == nil)

        // Absent capability means no push target.
        let without = Data(#"{"theming":{"name":"Nextcloud"}}"#.utf8)
        #expect(ServerEventCoordinator.pushTarget(from: CapabilitySet(version: version, raw: without), requested: [.notifications], accountAddress: account) == nil)
    }

    @Test("Unauthorized Classification")
    func unauthorizedClassification() {
        #expect(ServerEventCoordinator.isUnauthorized(RainmakerError.credentialsRequired))
        #expect(ServerEventCoordinator.isUnauthorized(RainmakerError.unexpectedStatus(code: 401)))
        #expect(ServerEventCoordinator.isUnauthorized(RainmakerError.unexpectedStatus(code: 500)) == false)
        #expect(ServerEventCoordinator.isUnauthorized(RainmakerError.notFound) == false)
    }
}
