import Foundation
import UserNotifications

/// Describes an incoming CallKit call carried by a push notification.
///
/// A doorbell (or any other WebRTC caller) sends a notification whose `userInfo` contains a
/// `callkit` dictionary. When present, the app reports a system call instead of (or in addition to)
/// showing a banner, and — once the call is answered — navigates to the configured screen.
///
/// Example `data` payload sent from Home Assistant:
/// ```yaml
/// data:
///   # standard notification fields are reused for the call UI
///   attachment:
///     url: /api/camera_proxy/camera.front_door
///   callkit:
///     caller_name: "Front Door"        # optional, falls back to the notification title
///     navigate_path: "/lovelace/doorbell"  # opened when the call is answered
///     video: true                      # optional, defaults to true (WebRTC video doorbell)
///     handle: "front_door"             # optional caller handle/identifier
/// ```
public struct CallKitNotificationPayload: Equatable {
    /// Name shown on the system call screen. Falls back to the notification title, then a default.
    public let callerName: String
    /// Path/URL opened in the frontend when the call is answered. `nil` means "stay where we are".
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
    /// not a CallKit call.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let callkit = userInfo["callkit"] as? [String: Any] else {
            return nil
        }

        let title = CallKitNotificationPayload.title(from: userInfo)
        let callerName = (callkit["caller_name"] as? String)?.nonEmpty
            ?? title
            ?? L10n.Callkit.IncomingCall.defaultCaller

        let navigatePath = (callkit["navigate_path"] as? String)?.nonEmpty
            ?? (callkit["url"] as? String)?.nonEmpty

        let hasVideo = callkit["video"] as? Bool ?? true

        let handle = (callkit["handle"] as? String)?.nonEmpty ?? callerName

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
}

private extension String {
    /// Returns `nil` when the string is empty, so callers can use `??` to fall back.
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
