@testable import Shared
import XCTest

final class CallKitNotificationPayloadTests: XCTestCase {
    func testReturnsNilWhenNotAnIncomingCallCommand() {
        XCTAssertNil(CallKitNotificationPayload(userInfo: [:]))
        // A standard notification with a title but no command is not a call.
        XCTAssertNil(CallKitNotificationPayload(userInfo: ["aps": ["alert": ["title": "Front Door"]]]))
        // A different command is not a call.
        XCTAssertNil(CallKitNotificationPayload(userInfo: ["homeassistant": ["command": "clear_notification"]]))
    }

    func testParsesUnifiedPayload() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "aps": ["alert": ["title": "Front Door"]],
            "url": "/lovelace/doorbell",
            "homeassistant": [
                "command": "incoming_call",
                "video": true,
                "handle": "front_door",
            ],
        ]))

        XCTAssertEqual(payload.callerName, "Front Door")
        XCTAssertEqual(payload.navigatePath, "/lovelace/doorbell")
        XCTAssertTrue(payload.hasVideo)
        XCTAssertEqual(payload.handle, "front_door")
    }

    func testCallerNameComesFromNotificationTitle() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "aps": ["alert": ["title": "Back Door"]],
            "url": "/lovelace/doorbell",
            "homeassistant": ["command": "incoming_call"],
        ]))

        XCTAssertEqual(payload.callerName, "Back Door")
        // Handle defaults to the caller name when not provided.
        XCTAssertEqual(payload.handle, "Back Door")
    }

    func testFallsBackToDefaultCallerWhenNoTitle() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "homeassistant": ["command": "incoming_call"],
        ]))

        XCTAssertFalse(payload.callerName.isEmpty)
        XCTAssertNil(payload.navigatePath)
    }

    func testDefaultsVideoToTrueAndAllowsDisabling() throws {
        let withDefault = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "homeassistant": ["command": "incoming_call"],
        ]))
        XCTAssertTrue(withDefault.hasVideo)

        let audioOnly = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "homeassistant": ["command": "incoming_call", "video": false],
        ]))
        XCTAssertFalse(audioOnly.hasVideo)
    }

    func testSupportsUriAndClickActionForNavigation() throws {
        let uriPayload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "uri": "/lovelace/doorbell",
            "homeassistant": ["command": "incoming_call"],
        ]))
        XCTAssertEqual(uriPayload.navigatePath, "/lovelace/doorbell")

        let clickActionPayload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "clickAction": "/lovelace/garage",
            "homeassistant": ["command": "incoming_call"],
        ]))
        XCTAssertEqual(clickActionPayload.navigatePath, "/lovelace/garage")
    }

    func testIgnoresEmptyStringsAndFallsBack() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "url": "",
            "aps": ["alert": ["title": ""]],
            "homeassistant": ["command": "incoming_call", "handle": ""],
        ]))

        XCTAssertNil(payload.navigatePath)
        XCTAssertFalse(payload.callerName.isEmpty)
        // Empty handle falls back to the caller name.
        XCTAssertEqual(payload.handle, payload.callerName)
    }
}
