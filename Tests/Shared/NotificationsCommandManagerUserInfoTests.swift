import Foundation
import PromiseKit
@testable import Shared
import XCTest

/// Verifies that `NotificationCommandManager` forwards the full notification `userInfo` (not just
/// the `homeassistant` command dictionary) to handlers that opt in via `handle(_:userInfo:)`.
/// This is what lets the incoming-call handler reuse standard notification fields such as the
/// notification `title` and the top-level `url`, which live outside `homeassistant`.
final class NotificationsCommandManagerUserInfoTests: XCTestCase {
    private final class SpyHandler: NotificationCommandHandler {
        var receivedCommandDict: [String: Any]?
        var receivedUserInfo: [AnyHashable: Any]?

        func handle(_ payload: [String: Any]) -> Promise<Void> {
            receivedCommandDict = payload
            return .value(())
        }

        func handle(_ payload: [String: Any], userInfo: [AnyHashable: Any]) -> Promise<Void> {
            receivedCommandDict = payload
            receivedUserInfo = userInfo
            return .value(())
        }
    }

    func testForwardsFullUserInfoToHandler() throws {
        let sut = NotificationCommandManager()
        let handler = SpyHandler()
        sut.register(command: "incoming_call", handler: handler)

        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Front Door"]],
            "url": "/lovelace/doorbell",
            "homeassistant": [
                "command": "incoming_call",
                "video": true,
            ] as [String: Any],
        ]

        XCTAssertNoThrow(try hang(sut.handle(userInfo)))

        // The command dictionary is the `homeassistant` sub-dictionary.
        XCTAssertEqual(handler.receivedCommandDict?["command"] as? String, "incoming_call")
        // The full userInfo carries the standard notification fields that live outside it.
        let received = try XCTUnwrap(handler.receivedUserInfo)
        XCTAssertEqual(received["url"] as? String, "/lovelace/doorbell")
        let aps = try XCTUnwrap(received["aps"] as? [String: Any])
        let alert = try XCTUnwrap(aps["alert"] as? [String: Any])
        XCTAssertEqual(alert["title"] as? String, "Front Door")
    }
}
