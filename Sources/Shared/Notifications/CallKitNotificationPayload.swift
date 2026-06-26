import Foundation
import UserNotifications

/// Describes an incoming CallKit call carried by a push notification.
///
/// An incoming call reuses the standard notification command mechanism: the push sets
/// `homeassistant.command = "incoming_call"`. Caller name and answer navigation reuse the existing
/// notification fields (the notification `title` and the top-level `url`) rather than introducing
/// call-specific aliases, so a doorbell automation looks like any other actionable notification with
/// a couple of extra, genuinely call-specific options (`video`, `handle`).
///
/// Example `data` payload sent from Home Assistant:
/// ```yaml
/// data:
///   # standard notification fields drive the call UI
///   title: "Front Door"               # shown as the caller name on the system call screen
///   url: "/lovelace/doorbell"          # opened in the frontend when the call is answered
///   attachment:
///     url: /api/camera_proxy/camera.front_door  # used as the call icon when available
///   homeassistant:
///     command: "incoming_call"         # routes the push to the CallKit handler
///     video: true                      # optional, defaults to true (WebRTC video doorbell)
///     handle: "front_door"             # optional caller handle/identifier
/// ```
public struct CallKitNotificationPayload: Equatable {
    /// The `homeassistant.command` value that identifies an incoming call notification.
    public static let command = "incoming_call"

    /// Name shown on the system call screen. Reuses the notification title, then a default.
    public let callerName: String
    /// Path/URL opened in the frontend when the call is answered. `nil` means "stay where we are".
    /// Reuses the standard notification `url`/`uri`/`clickAction` field.
    public let navigatePath: String?
    /// Whether the call offers video. Defaults to `true` for WebRTC video doorbells.
    public let hasVideo: Bool
    /// Opaque handle used by CallKit to identify the caller (for recents/redial).
    public let handle: String

    public init(callerName: String, navigatePath: String?, hasVideo: Bool, handle: String) {
        self.callerName = callerName
        self.navigatePath = navigatePath
        self.hasVideo = hasVideo
        self.handle = handle
    }

    /// Builds a payload from a notification's `userInfo`, or returns `nil` when the notification is
    /// not an incoming-call command.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let command = userInfo["homeassistant"] as? [String: Any],
              (command["command"] as? String) == CallKitNotificationPayload.command else {
            return nil
        }

        let callerName = CallKitNotificationPayload.title(from: userInfo)
            ?? L10n.CallKit.IncomingCall.defaultCaller

        let navigatePath = CallKitNotificationPayload.navigationURL(from: userInfo)

        let hasVideo = command["video"] as? Bool ?? true

        let handle = (command["handle"] as? String)?.nonEmpty ?? callerName

        self.init(callerName: callerName, navigatePath: navigatePath, hasVideo: hasVideo, handle: handle)
    }

    /// Extracts the notification title from the standard `aps.alert.title` location.
    private static func title(from userInfo: [AnyHashable: Any]) -> String? {
        guard let aps = userInfo["aps"] as? [String: Any] else {
            return nil
        }

        if let alert = aps["alert"] as? [String: Any] {
            return (alert["title"] as? String)?.nonEmpty
        }

        return nil
    }

    /// Resolves the answer-navigation URL from the standard notification fields, mirroring the
    /// global URL handling in `NotificationManager` (`url`/`uri`/`clickAction`).
    private static func navigationURL(from userInfo: [AnyHashable: Any]) -> String? {
        let urlValue = ["url", "uri", "clickAction"].compactMap { userInfo[$0] }.first
        return (urlValue as? String)?.nonEmpty
    }
}

private extension String {
    /// Returns `nil` when the string is empty, so callers can use `??` to fall back.
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
