import SwiftUI

@main
struct AnthologyApp: App {
    @UIApplicationDelegateAdaptor(AnthologyAppDelegate.self) var appDelegate
    @StateObject private var store = BridgeStore()
    @StateObject private var push = PushManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(push)
                .preferredColorScheme(.dark)
                .task {
                    push.bridgeStore = store
                    await store.bootstrap()
                    await push.bootstrap()
                }
                .onChange(of: store.connectionState) { _, _ in
                    // Re-register on every successful connect so a freshly
                    // re-paired Mac picks up the existing device token.
                    Task { await push.sendToBridge() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NotificationDelegate.didTapNotification)) { note in
                    if let sid = note.userInfo?["sessionId"] as? String, !sid.isEmpty {
                        store.pendingDeepLinkSessionId = sid
                    }
                }
        }
    }
}
