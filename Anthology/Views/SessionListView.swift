import SwiftUI

enum SessionsTab: String, CaseIterable, Identifiable {
    case list, missionControl, schedules
    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: return "List"
        case .missionControl: return "Grid"
        case .schedules: return "Schedules"
        }
    }
    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .missionControl: return "square.grid.2x2"
        case .schedules: return "clock"
        }
    }
}

struct SessionListView: View {
    @EnvironmentObject var store: BridgeStore
    @AppStorage("anthology.sessionsTab") private var tabRaw: String = SessionsTab.list.rawValue
    @State private var showingSettings = false
    @State private var showingSpawn = false
    @State private var navPath: [SessionMeta] = []

    private var tab: Binding<SessionsTab> {
        Binding(
            get: { SessionsTab(rawValue: tabRaw) ?? .list },
            set: {
                if tabRaw != $0.rawValue { HapticManager.shared.selection() }
                tabRaw = $0.rawValue
            }
        )
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                connectionBanner
                tabPicker
                Divider()
                Group {
                    switch tab.wrappedValue {
                    case .list:
                        listBody
                    case .missionControl:
                        MissionControlView()
                    case .schedules:
                        SchedulesView()
                    }
                }
            }
            .navigationTitle(store.server?.serverName ?? "Anthology")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Settings")
                }
                if tab.wrappedValue != .schedules {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingSpawn = true }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Spawn session")
                        .disabled(store.connectionState != .connected)
                    }
                }
            }
            .navigationDestination(for: SessionMeta.self) { session in
                SessionDetailView(session: session)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSpawn) {
                SpawnView()
            }
            .onChange(of: store.pendingDeepLinkSessionId) { _, sid in
                guard let sid = sid else { return }
                if let target = store.sessions.first(where: { $0.id == sid }) {
                    navPath = [target]
                } else {
                    // Session list might not be populated yet; refresh and try once.
                    Task {
                        await store.refreshSessions()
                        if let t = store.sessions.first(where: { $0.id == sid }) {
                            navPath = [t]
                        }
                    }
                }
                store.pendingDeepLinkSessionId = nil
                tabRaw = SessionsTab.list.rawValue
            }
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        if case .connected = store.connectionState {
            // No banner when healthy.
            EmptyView()
        } else {
            HStack(spacing: 10) {
                Image(systemName: bannerIcon)
                    .foregroundStyle(bannerTint)
                    .imageScale(.small)
                Text(store.connectionState.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    Task { await store.reconnectIfNeeded() }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(bannerTint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(bannerTint.opacity(0.12))
        }
    }

    private var bannerTint: Color {
        switch store.connectionState {
        case .connecting, .reconnecting: return .orange
        case .failed: return .red
        default: return .gray
        }
    }
    private var bannerIcon: String {
        switch store.connectionState {
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .reconnecting: return "arrow.clockwise.circle"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "wifi.slash"
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 10) {
            connectionBadge
            Spacer()
            Picker("View", selection: tab) {
                ForEach(SessionsTab.allCases) { t in
                    Label(t.label, systemImage: t.systemImage).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(store.connectionState.label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var listBody: some View {
        List {
            if store.sessions.isEmpty {
                Text("No sessions yet. Tap + to spawn one.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(store.sessions) { session in
                    NavigationLink(value: session) {
                        row(for: session)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refreshSessions() }
    }

    private func row(for session: SessionMeta) -> some View {
        let status = store.sessionStatus[session.id] ?? session.status
        return HStack(spacing: 12) {
            Rectangle()
                .fill(Color(hex: session.color))
                .frame(width: 4)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(status: status, size: 8)
                    Text(session.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let tag = session.tag, !tag.isEmpty {
                        Text(tag)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(hex: session.color).opacity(0.2), in: Capsule())
                            .foregroundStyle(Color(hex: session.color))
                    }
                }
                Text(session.cwd)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            Text(status.label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
