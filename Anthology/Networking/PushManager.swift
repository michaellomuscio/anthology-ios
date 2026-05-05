import Foundation
import UIKit
import UserNotifications

/// Owns APNs registration. UIApplicationDelegateAdaptor in AnthologyApp wires
/// the system delegate hooks into this singleton.
@MainActor
final class PushManager: ObservableObject {
    static let shared = PushManager()

    @Published private(set) var deviceToken: String?
    @Published private(set) var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?

    /// The store needs to be wired in once the app's @StateObject is alive.
    weak var bridgeStore: BridgeStore?

    private init() {}

    /// Called from .task on the root view. Idempotent.
    func bootstrap() async {
        await refreshPermissionStatus()
        if permissionStatus == .notDetermined {
            await requestAuthorization()
        } else if permissionStatus == .authorized || permissionStatus == .provisional {
            await registerWithAPNs()
        }
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermissionStatus()
            if granted { await registerWithAPNs() }
        } catch {
            lastError = "Notification permission failed: \(error.localizedDescription)"
        }
    }

    func registerWithAPNs() async {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func refreshPermissionStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = s.authorizationStatus
    }

    /// Called by the AppDelegate when APNs returns a device token.
    func didRegister(deviceToken raw: Data) {
        let hex = raw.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        lastError = nil
        Task { await sendToBridge() }
    }

    /// Called by the AppDelegate on registration failure.
    func didFailToRegister(error: Error) {
        lastError = "APNs registration failed: \(error.localizedDescription)"
    }

    /// Push the current device token to the connected Mac. Safe to call any
    /// number of times; the bridge accepts re-registration as an update.
    func sendToBridge() async {
        guard let token = deviceToken, let store = bridgeStore else { return }
        await store.registerPushToken(token, environment: aPSEnvironment())
    }

    /// Determined by the entitlement at build time. Debug builds default to
    /// `development`, release to `production`. SwiftTerm's Apple-Push pattern.
    private func aPSEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

/// UIKit AppDelegate shim. SwiftUI's @UIApplicationDelegateAdaptor lets us
/// receive the only-via-UIKit registration callbacks while keeping the app
/// architecture pure SwiftUI everywhere else.
final class AnthologyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushManager.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushManager.shared.didFailToRegister(error: error)
        }
    }
}

/// Foreground presentation + tap routing. We surface the alert in-app even
/// while the user is looking at it (so they don't miss waiting state) and
/// hand the userInfo dict off to a NotificationCenter event for the SwiftUI
/// layer to react to (deep-link to the right session).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    static let didTapNotification = Notification.Name("anthology.didTapNotification")

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(
            name: NotificationDelegate.didTapNotification,
            object: nil,
            userInfo: userInfo
        )
        completionHandler()
    }
}
