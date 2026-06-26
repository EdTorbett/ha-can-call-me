@testable import Shared
import XCTest

final class CallKitNotificationPayloadTests: XCTestCase {
    func testReturnsNilWhenNoCallKitPayload() {
        XCTAssertNil(CallKitNotificationPayload(userInfo: [:]))
        XCTAssertNil(CallKitNotificationPayload(userInfo: ["aps": ["alert": ["title": "Front Door"]]]))
    }

    func testParsesFullPayload() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "callkit": [
                "caller_name": "Front Door",
                "navigate_path": "/lovelace/doorbell",
                "video": true,
                "handle": "front_door",
            ],
        ]))

        XCTAssertEqual(payload.callerName, "Front Door")
        XCTAssertEqual(payload.navigatePath, "/lovelace/doorbell")
        XCTAssertTrue(payload.hasVideo)
        XCTAssertEqual(payload.handle, "front_door")
    }

    func testFallsBackToNotificationTitleForCallerName() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "aps": ["alert": ["title": "Back Door"]],
            "callkit": ["navigate_path": "/lovelace/doorbell"],
        ]))

        XCTAssertEqual(payload.callerName, "Back Door")
        // Handle defaults to the caller name when not provided.
        XCTAssertEqual(payload.handle, "Back Door")
    }

    func testDefaultsVideoToTrueAndAllowsDisabling() throws {
        let withDefault = try XCTUnwrap(CallKitNotificationPayload(userInfo: ["callkit": [:]]))
        XCTAssertTrue(withDefault.hasVideo)

        let audioOnly = try XCTUnwrap(CallKitNotificationPayload(userInfo: ["callkit": ["video": false]]))
        XCTAssertFalse(audioOnly.hasVideo)
    }

    func testSupportsUrlAliasForNavigatePath() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "callkit": ["url": "/lovelace/doorbell"],
        ]))

        XCTAssertEqual(payload.navigatePath, "/lovelace/doorbell")
    }

    func testIgnoresEmptyStringsAndFallsBack() throws {
        let payload = try XCTUnwrap(CallKitNotificationPayload(userInfo: [
            "callkit": [
                "caller_name": "",
                "navigate_path": "",
            ],
        ]))

        XCTAssertNil(payload.navigatePath)
        XCTAssertFalse(payload.callerName.isEmpty)
    }
}
