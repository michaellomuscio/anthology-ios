import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BridgeStore
    @EnvironmentObject var push: PushManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDisconnect = false
    @AppStorage(HapticManager.userDefaultsKey) private var hapticsEnabled: Bool = true
    @AppStorage(SoundManager.userDefaultsKey) private var soundEnabled: Bool = false

    private func runHapticDiagnostic() {
        // Fire every flavor on a 250ms cadence so the user can feel each one
        // distinctly. If they feel nothing, the problem is below our layer.
        HapticManager.shared.prepare()
        let h = HapticManager.shared
        h.heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { h.medium() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { h.light() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) { h.success() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.10) { h.warning() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) { h.error() }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let server = store.server {
                    Section("Connected Mac") {
                        LabeledContent("Name", value: server.serverName)
                        LabeledContent("Address", value: server.address)
                        LabeledContent("Server version", value: server.serverVersion)
                        LabeledContent("Status", value: store.connectionState.label)
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmingDisconnect = true
                        } label: {
                            Label("Forget this Mac", systemImage: "trash")
                        }
                    } footer: {
                        Text("Forgetting deletes the bearer token from this device. The Mac will still show this device as paired until you revoke it on the Mac.")
                    }
                }

                Section {
                    LabeledContent("Permission", value: pushPermissionLabel)
                    LabeledContent("Device token", value: push.deviceToken == nil ? "Not registered" : "\(String(push.deviceToken!.prefix(10)))…")
                    if push.permissionStatus == .denied {
                        Text("Open the iOS Settings app → Anthology → Notifications and turn them on, then re-open this screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if push.permissionStatus == .notDetermined {
                        Button("Request notification permission") {
                            Task { await push.requestAuthorization() }
                        }
                    }
                    if let err = push.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Push notifications")
                } footer: {
                    Text("Wakes the phone when a session goes waiting/error while this app is closed. Requires the Mac to have a Cloudflare Worker URL + secret configured (see anthology-push-worker/README.md).")
                }

                Section {
                    Toggle(isOn: $hapticsEnabled) {
                        Label("Haptic feedback", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    }
                    .onChange(of: hapticsEnabled) { _, on in
                        if on { HapticManager.shared.heavy() }
                    }
                    Toggle(isOn: $soundEnabled) {
                        Label("Sound effects", systemImage: "speaker.wave.2")
                    }
                    .onChange(of: soundEnabled) { _, on in
                        if on { SoundManager.shared.previewWaiting() }
                    }

                    // Diagnostic — fires every haptic flavor in sequence so the user
                    // can verify their device actually produces haptics for this app.
                    // If THIS does nothing, the issue is iOS-level (System Haptics
                    // turned off in Settings → Sounds & Haptics, or Low Power Mode).
                    Button {
                        runHapticDiagnostic()
                    } label: {
                        Label("Test haptics", systemImage: "waveform.path")
                    }
                    .disabled(!hapticsEnabled)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Haptics fire when a session changes state (waiting / idle / error). If Test haptics does nothing, open iOS Settings → Sounds & Haptics and make sure System Haptics is on, and that Low Power Mode is off. Sounds layer a brief system tone on top — silenced by your ringer switch.")
                }

                Section("About") {
                    LabeledContent("App version", value: appVersion)
                    LabeledContent("Bridge protocol", value: "v1")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Forget this Mac?", isPresented: $confirmingDisconnect) {
                Button("Forget", role: .destructive) {
                    store.disconnectAndForget()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var pushPermissionLabel: String {
        switch push.permissionStatus {
        case .authorized: return "Allowed"
        case .provisional: return "Allowed (provisional)"
        case .denied: return "Denied"
        case .notDetermined: return "Not yet asked"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}
