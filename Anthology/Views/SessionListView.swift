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
    /// Current group filter. Empty = All. "_ungrouped" = sessions without a groupId.
    /// "_pinned" = pinned filter. Otherwise a real groupId.
    @State private var groupFilter: String = ""
    @State private var killTarget: SessionMeta? = nil

    private var tab: Binding<SessionsTab> {
        Binding(
            get: { SessionsTab(rawValue: tabRaw) ?? .list },
            set: {
                // Light impact rather than selection — selection is so subtle on
                // newer Taptic Engines that it can be missed entirely.
                if tabRaw != $0.rawValue { HapticManager.shared.light() }
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

    private var filteredSessions: [SessionMeta] {
        switch groupFilter {
        case "":
            return store.sessions
        case "_pinned":
            return store.sessions.filter { $0.pinned }
        case "_ungrouped":
            let validGroupIds = Set(store.groups.map { $0.id })
            return store.sessions.filter {
                ($0.groupId == nil) || !($0.groupId.flatMap { validGroupIds.contains($0) } ?? false)
            }
        default:
            return store.sessions.filter { $0.groupId == groupFilter }
        }
    }

    @ViewBuilder
    private var groupFilterChips: some View {
        if !store.groups.isEmpty || store.sessions.contains(where: { $0.pinned }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip(id: "", label: "All", count: store.sessions.count)
                    if store.sessions.contains(where: { $0.pinned }) {
                        filterChip(id: "_pinned", label: "Pinned",
                                   count: store.sessions.filter { $0.pinned }.count)
                    }
                    ForEach(store.groups) { g in
                        let n = store.sessions.filter { $0.groupId == g.id }.count
                        filterChip(id: g.id, label: g.name, count: n)
                    }
                    if store.sessions.contains(where: { $0.groupId == nil }) {
                        let n = store.sessions.filter { $0.groupId == nil }.count
                        filterChip(id: "_ungrouped", label: "Ungrouped", count: n)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    private func filterChip(id: String, label: String, count: Int) -> some View {
        let active = groupFilter == id
        return Button {
            HapticManager.shared.selection()
            groupFilter = id
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption.weight(active ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(active ? Color.accentColor : Color.gray.opacity(0.4)))
            .foregroundStyle(active ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private var listBody: some View {
        VStack(spacing: 0) {
            groupFilterChips
            List {
                let sessions = filteredSessions
                if sessions.isEmpty {
                    Text(store.sessions.isEmpty
                         ? "No sessions yet. Tap + to spawn one."
                         : "No sessions in this group.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            row(for: session)
                        }
                        .contextMenu {
                            sessionContextMenu(for: session)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await store.refreshSessions() }
        }
        .alert("Kill session?",
               isPresented: Binding(get: { killTarget != nil }, set: { if !$0 { killTarget = nil } })) {
            Button("Kill", role: .destructive) {
                if let t = killTarget {
                    HapticManager.shared.heavy()
                    Task { await store.kill(sessionId: t.id) }
                }
                killTarget = nil
            }
            Button("Cancel", role: .cancel) { killTarget = nil }
        } message: {
            if let t = killTarget {
                Text("Terminates Claude for \"\(t.name)\". The session row stays in the list with a dead status until you restart it from the Mac.")
            }
        }
    }

    @ViewBuilder
    private func sessionContextMenu(for session: SessionMeta) -> some View {
        // Open is the implicit tap action — surface it in the menu for discovery.
        Button {
            HapticManager.shared.light()
            navPath = [session]
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }

        if !store.groups.isEmpty {
            Menu {
                Button {
                    Task {
                        HapticManager.shared.selection()
                        await store.setSessionGroup(sessionId: session.id, groupId: nil)
                    }
                } label: {
                    Label("Ungrouped", systemImage: session.groupId == nil ? "checkmark" : "")
                }
                ForEach(store.groups) { g in
                    Button {
                        Task {
                            HapticManager.shared.selection()
                            await store.setSessionGroup(sessionId: session.id, groupId: g.id)
                        }
                    } label: {
                        if session.groupId == g.id {
                            Label(g.name, systemImage: "checkmark")
                        } else {
                            Text(g.name)
                        }
                    }
                }
            } label: {
                Label("Move to folder", systemImage: "folder")
            }
        }

        Divider()

        Button(role: .destructive) {
            killTarget = session
        } label: {
            Label("Kill session", systemImage: "stop.circle")
        }
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
