import CallKit
import Foundation
import PromiseKit
import Shared
import UserNotifications

/// Bridges incoming call notifications (e.g. a WebRTC doorbell) to the system CallKit UI.
///
/// When a notification carrying a `callkit` payload is received, `reportIncomingCall(userInfo:)`
/// presents a native incoming-call screen showing the notification title (caller name) and, when
/// available, the notification thumbnail. Answering the call navigates the frontend to the
/// configured screen, reusing the same routing as a notification tap.
final class CallKitManager: NSObject {
    /// Context for the single in-flight call. The doorbell scenario only ever needs one call at a
    /// time, so a fresh provider is created per call (which also lets the thumbnail/icon vary).
    private struct ActiveCall {
        let uuid: UUID
        let provider: CXProvider
        let server: Server
        let navigatePath: String?
    }

    private var activeCall: ActiveCall?

    /// Reports an incoming call for the given notification payload, if it describes one.
    func reportIncomingCall(userInfo: [AnyHashable: Any]) {
        guard let payload = CallKitNotificationPayload(userInfo: userInfo) else {
            return
        }

        // Reuse the notification infrastructure: build content so we can resolve the originating
        // server and download any attachment thumbnail exactly as a banner notification would.
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo

        guard let server = Current.servers.server(for: content) else {
            Current.Log.error("CallKit: ignoring incoming call, unable to resolve server")
            return
        }

        Current.Log.info("CallKit: reporting incoming call from \(payload.callerName)")

        firstly {
            thumbnailData(for: content, server: server)
        }.done { [weak self] imageData in
            self?.presentCall(payload: payload, server: server, iconData: imageData)
        }
    }

    /// Best-effort download of the notification attachment as raw image data for the call icon.
    private func thumbnailData(for content: UNNotificationContent, server: Server) -> Guarantee<Data?> {
        guard content.userInfo["attachment"] != nil, let api = Current.api(for: server) else {
            return .value(nil)
        }

        return Guarantee { seal in
            Current.notificationAttachmentManager.downloadAttachment(from: content, api: api).done { url in
                seal(try? Data(contentsOf: url))
            }.catch { error in
                Current.Log.info("CallKit: no thumbnail for call (\(error.localizedDescription))")
                seal(nil)
            }
        }
    }

    private func presentCall(payload: CallKitNotificationPayload, server: Server, iconData: Data?) {
        // Replace any previous ringing call; a new doorbell press supersedes the old one.
        endActiveCall()

        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = payload.hasVideo
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        if let iconData {
            // The thumbnail shown on the system call screen.
            configuration.iconTemplateImageData = iconData
        }

        let provider = CXProvider(configuration: configuration)
        provider.setDelegate(self, queue: nil)

        let uuid = UUID()
        activeCall = ActiveCall(
            uuid: uuid,
            provider: provider,
            server: server,
            navigatePath: payload.navigatePath
        )

        let update = CXCallUpdate()
        update.localizedCallerName = payload.callerName
        update.remoteHandle = CXHandle(type: .generic, value: payload.handle)
        update.hasVideo = payload.hasVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error {
                Current.Log.error("CallKit: failed to report incoming call: \(error.localizedDescription)")
                self?.endActiveCall()
            }
        }
    }

    private func endActiveCall() {
        guard let call = activeCall else { return }
        call.provider.invalidate()
        activeCall = nil
    }

    private func navigate(for call: ActiveCall) {
        guard let path = call.navigatePath else { return }
        let server = call.server
        Current.Log.info("CallKit: navigating to \(path) after call answered")
        Current.sceneManager.appCoordinator.done {
            $0.open(from: .notification, server: server, urlString: path, isComingFromAppIntent: false)
        }
    }
}

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        if activeCall?.provider === provider {
            activeCall = nil
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = activeCall, call.uuid == action.callUUID else {
            action.fail()
            return
        }

        navigate(for: call)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        if activeCall?.uuid == action.callUUID {
            endActiveCall()
        }
    }
}
