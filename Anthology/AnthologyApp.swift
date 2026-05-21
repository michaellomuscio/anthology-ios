import SwiftUI

@main
struct AnthologyApp: App {
    @UIApplicationDelegateAdaptor(AnthologyAppDelegate.self) var appDelegate
    @StateObject private var store = BridgeStore()
    @StateObject private var push = PushManager.shared
    @Environment(\.scenePhase) private var scenePhase

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
                .onChange(of: scenePhase) { _, newPhase in
                    // Foreground after background: iOS may have left the WS in a
                    // half-dead state (receive never returns, scheduleReconnect
                    // never trips). Nudge the client to refresh its socket so the
                    // user doesn't have to delete + re-pair just to come back online.
                    if newPhase == .active {
                        Task { await store.reconnectIfNeeded() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NotificationDelegate.didTapNotification)) { note in
                    if let sid = note.userInfo?["sessionId"] as? String, !sid.isEmpty {
                        store.pendingDeepLinkSessionId = sid
                    }
                }
        }
    }
}
