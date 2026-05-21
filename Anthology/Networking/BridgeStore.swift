import Foundation
import Combine

/// SwiftUI-facing observable that wraps the BridgeClient and translates events
/// into UI state. One BridgeStore per app instance; servers are switchable.
@MainActor
final class BridgeStore: ObservableObject {
    @Published var server: ServerHandle?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var sessions: [SessionMeta] = []
    @Published var sessionData: [String: String] = [:]   // sessionId -> live cumulative buffer
    @Published var sessionStatus: [String: SessionStatus] = [:]
    @Published var schedules: [Schedule] = []
    @Published var workers: [Worker] = []
    @Published var groups: [SessionGroup] = []
    @Published var lastError: String?
    /// Set when a push notification is tapped or another deep-link source asks
    /// the UI to navigate to a specific session. SessionListView watches this
    /// and pushes a SessionDetailView, then clears it.
    @Published var pendingDeepLinkSessionId: String?

    private var client: BridgeClient?
    private var subscribedSessionIds: Set<String> = []
    private var wildcardSubscribed = false
    private(set) var serverInfo: (name: String, version: String)?
    @Published var recentDirs: [String] = []

    /// Called once at launch to restore the most recently used server, if any.
    func bootstrap() async {
        let servers = ServerStore.list()
        // Pick the most recently paired server as the default. Multi-server UI
        // can come later — for v1 we connect to one Mac at a time.
        guard let server = servers.sorted(by: { $0.pairedAt > $1.pairedAt }).first else {
            return
        }
        await connect(to: server)
    }

    func connect(to server: ServerHandle) async {
        client?.disconnect()
        guard let token = KeychainStore.loadToken(account: server.keychainAccount) else {
            lastError = "Token missing for \(server.serverName) — re-pair required."
            return
        }
        let c = BridgeClient(server: server, token: token)
        c.setStateHandler { [weak self] state in
            Task { @MainActor in self?.connectionState = state }
        }
        c.setEventHandler { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        client = c
        self.server = server
        c.connect()
        // Wait until connected (or fail) before fetching state.
        await waitForConnection()
        await refreshAll()
    }

    /// Called when the app returns to the foreground (or the user taps a
    /// reconnect button). If we already have a paired server, force the live
    /// client to refresh its socket; if we lost the client (cold launch after
    /// iOS killed us), recreate it from stored credentials.
    func reconnectIfNeeded() async {
        // No server paired — nothing to reconnect to.
        guard let s = server ?? ServerStore.list().sorted(by: { $0.pairedAt > $1.pairedAt }).first else {
            return
        }
        if let c = client {
            c.forceReconnect()
            // Wait briefly so SwiftUI sees the .connected transition before any
            // immediately-following refresh attempt runs against a half-up client.
            await waitForConnection(timeout: 6)
            if case .connected = connectionState {
                await refreshAll()
            }
            return
        }
        // No live client — full bootstrap path. connect(to:) handles the
        // KeychainStore lookup and the BridgeClient construction.
        await connect(to: s)
    }

    func disconnectAndForget() {
        client?.disconnect()
        client = nil
        if let s = server {
            ServerStore.remove(tokenId: s.tokenId)
        }
        server = nil
        sessions = []
        sessionData = [:]
        sessionStatus = [:]
    }

    // MARK: - Public API used by views

    func refreshAll() async {
        await refreshSessions()
        await refreshSchedules()
        await refreshWorkers()
        await refreshGroups()
    }

    func refreshWorkers() async {
        guard let c = client else { return }
        do {
            let ack = try await c.send(type: "list_workers", payload: [:])
            if let result = ack.raw["result"]?.dictValue,
               let arr = result["workers"] {
                let data = try JSONEncoder().encode(arr)
                self.workers = (try? JSONDecoder().decode([Worker].self, from: data)) ?? []
            }
        } catch { /* older Macs don't have list_workers — silent fallback */ }
    }

    func refreshGroups() async {
        guard let c = client else { return }
        do {
            let ack = try await c.send(type: "list_groups", payload: [:])
            if let result = ack.raw["result"]?.dictValue,
               let arr = result["groups"] {
                let data = try JSONEncoder().encode(arr)
                self.groups = (try? JSONDecoder().decode([SessionGroup].self, from: data)) ?? []
            }
        } catch { /* older Macs don't have list_groups — silent fallback */ }
    }

    func setSessionGroup(sessionId: String, groupId: String?) async {
        guard let c = client else { return }
        var payload: [String: AnyCodable] = ["sessionId": .init(sessionId)]
        if let g = groupId { payload["groupId"] = .init(g) }
        do {
            _ = try await c.send(type: "set_session_group", payload: payload)
            // The server fans a session_meta event which our handler picks up.
        } catch {
            lastError = "set_session_group failed: \(error)"
        }
    }

    func refreshSessions() async {
        guard let c = client else { return }
        do {
            let ack = try await c.send(type: "list_sessions", payload: [:])
            if let result = ack.raw["result"]?.dictValue,
               let arr = result["sessions"] {
                let data = try JSONEncoder().encode(arr)
                let parsed = try JSONDecoder().decode([SessionMeta].self, from: data)
                self.sessions = parsed
                for s in parsed { self.sessionStatus[s.id] = s.status }
            }
        } catch {
            self.lastError = "list_sessions failed: \(error)"
        }
    }

    func refreshSchedules() async {
        guard let c = client else { return }
        do {
            let ack = try await c.send(type: "list_schedules", payload: [:])
            if let result = ack.raw["result"]?.dictValue,
               let arr = result["schedules"] {
                let data = try JSONEncoder().encode(arr)
                self.schedules = (try? JSONDecoder().decode([Schedule].self, from: data)) ?? []
            }
        } catch { /* best effort */ }
    }

    func subscribe(to sessionId: String) async -> String? {
        guard let c = client else { return nil }
        guard !subscribedSessionIds.contains(sessionId) else {
            // Already subscribed — just return the cached buffer.
            return sessionData[sessionId]
        }
        subscribedSessionIds.insert(sessionId)
        do {
            _ = try await c.send(type: "subscribe", payload: [
                "sessionIds": .init([sessionId])
            ])
            // Pull the buffer snapshot once at subscribe time.
            let ack = try await c.send(type: "get_buffer", payload: [
                "sessionId": .init(sessionId)
            ])
            let snapshot = (ack.raw["result"]?.dictValue?["data"]?.stringValue) ?? ""
            self.sessionData[sessionId] = snapshot
            return snapshot
        } catch {
            self.lastError = "subscribe failed: \(error)"
            return nil
        }
    }

    func unsubscribe(from sessionId: String) {
        guard let c = client else { return }
        subscribedSessionIds.remove(sessionId)
        c.sendOneWay(type: "unsubscribe", payload: [
            "sessionIds": .init([sessionId])
        ])
    }

    /// Subscribe to every session for Mission Control grid previews. Idempotent.
    func subscribeAll() async {
        guard let c = client else { return }
        guard !wildcardSubscribed else { return }
        wildcardSubscribed = true
        do {
            _ = try await c.send(type: "subscribe", payload: ["sessionIds": .init("*")])
        } catch {
            wildcardSubscribed = false
            self.lastError = "subscribeAll failed: \(error)"
        }
    }

    func unsubscribeAll() {
        guard let c = client else { return }
        guard wildcardSubscribed else { return }
        wildcardSubscribed = false
        c.sendOneWay(type: "unsubscribe", payload: ["sessionIds": .init("*")])
        // Per-session subscriptions are still active on the server side; we
        // intentionally don't clear them so SessionDetailView keeps its stream.
    }

    func refreshRecentDirs() async {
        guard let c = client else { return }
        do {
            let ack = try await c.send(type: "list_recent_dirs", payload: [:])
            if let result = ack.raw["result"]?.dictValue,
               let arr = result["dirs"] {
                let data = try JSONEncoder().encode(arr)
                self.recentDirs = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
        } catch { /* best effort */ }
    }

    func sendInput(_ data: String, to sessionId: String) {
        guard let c = client else { return }
        c.sendOneWay(type: "send_input", payload: [
            "sessionId": .init(sessionId),
            "data": .init(data),
        ])
    }

    func sendPrompt(_ text: String, to sessionId: String) async {
        guard let c = client else { return }
        _ = try? await c.send(type: "send_prompt", payload: [
            "sessionId": .init(sessionId),
            "text": .init(text),
        ])
    }

    func resize(sessionId: String, cols: Int, rows: Int) {
        guard let c = client else { return }
        c.sendOneWay(type: "resize", payload: [
            "sessionId": .init(sessionId),
            "cols": .init(cols),
            "rows": .init(rows),
        ])
    }

    func kill(sessionId: String) async {
        guard let c = client else { return }
        _ = try? await c.send(type: "kill", payload: ["sessionId": .init(sessionId)])
        // Optimistic local drop — the server also broadcasts session_killed
        // which our handler picks up, but doing it here removes the row
        // instantly without waiting for the round-trip.
        sessions.removeAll { $0.id == sessionId }
        sessionStatus[sessionId] = nil
    }

    func upsertSchedule(_ s: Schedule) async -> Schedule? {
        guard let c = client else { return nil }
        do {
            let data = try JSONEncoder().encode(s)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            let ack = try await c.send(type: "upsert_schedule", payload: ["schedule": any])
            await refreshSchedules()
            if let result = ack.raw["result"]?.dictValue, let v = result["schedule"] {
                let d = try JSONEncoder().encode(v)
                return try? JSONDecoder().decode(Schedule.self, from: d)
            }
        } catch {
            self.lastError = "upsert_schedule failed: \(error)"
        }
        return nil
    }

    func deleteSchedule(id: String) async {
        guard let c = client else { return }
        _ = try? await c.send(type: "delete_schedule", payload: ["id": .init(id)])
        await refreshSchedules()
    }

    func runScheduleNow(id: String) async {
        guard let c = client else { return }
        _ = try? await c.send(type: "run_schedule_now", payload: ["id": .init(id)])
    }

    /// Forwards the APNs device token to the connected Mac so the push
    /// dispatcher can wake this phone when no client is connected.
    func registerPushToken(_ deviceToken: String, environment: String) async {
        guard let c = client else { return }
        _ = try? await c.send(type: "register_push_token", payload: [
            "deviceToken": .init(deviceToken),
            "environment": .init(environment),
        ])
    }

    func spawn(
        name: String,
        cwd: String,
        runClaude: Bool = true,
        tag: String? = nil,
        color: String? = nil,
        pm: Bool = false,
        agentTool: String? = nil,
        personaName: String? = nil,
        groupId: String? = nil
    ) async -> SessionMeta? {
        guard let c = client else { return nil }
        var payload: [String: AnyCodable] = [
            "name": .init(name),
            "cwd": .init(cwd),
            "runClaude": .init(runClaude),
            "pm": .init(pm),
        ]
        if let tag = tag, !tag.isEmpty { payload["tag"] = .init(tag) }
        if let color = color, !color.isEmpty { payload["color"] = .init(color) }
        if let agentTool = agentTool, !agentTool.isEmpty { payload["agentTool"] = .init(agentTool) }
        if let personaName = personaName, !personaName.isEmpty { payload["personaName"] = .init(personaName) }
        if let groupId = groupId, !groupId.isEmpty { payload["groupId"] = .init(groupId) }
        do {
            let ack = try await c.send(type: "spawn", payload: payload)
            if let result = ack.raw["result"]?.dictValue,
               let s = result["session"] {
                let data = try JSONEncoder().encode(s)
                return try JSONDecoder().decode(SessionMeta.self, from: data)
            }
        } catch {
            self.lastError = "spawn failed: \(error)"
        }
        return nil
    }

    // MARK: - Pairing entry points

    /// Pair with a Mac. On success, persists the server + token and connects.
    func pair(host: String, port: Int, code: String, label: String) async throws {
        let resp = try await PairingClient.pair(host: host, port: port, code: code, label: label)
        try KeychainStore.save(token: resp.token, account: resp.tokenId)
        let handle = ServerHandle(
            host: host, port: port,
            tokenId: resp.tokenId,
            serverName: resp.serverName,
            serverVersion: resp.serverVersion,
            pairedAt: Date().timeIntervalSince1970
        )
        ServerStore.upsert(handle)
        // Pairing is a milestone moment — the user just successfully linked a
        // device. Buzz + chime to confirm the action landed.
        HapticManager.shared.success()
        SoundManager.shared.success()
        await connect(to: handle)
    }

    // MARK: - Internals

    private func handle(_ event: BridgeEvent) {
        switch event {
        case .sessionData(let id, let data):
            // Append to live buffer; cap at ~1 MB to bound memory.
            let prior = sessionData[id] ?? ""
            let appended = prior + data
            sessionData[id] = appended.count > 1_000_000
                ? String(appended.suffix(1_000_000))
                : appended
        case .sessionStatus(let id, let status):
            let prev = sessionStatus[id]
            sessionStatus[id] = status
            if let i = sessions.firstIndex(where: { $0.id == id }) {
                sessions[i].status = status
            }
            // Fire haptic + sound on real transitions only (server re-emits the
            // same status often during heavy output).
            HapticManager.shared.sessionStatusTransition(from: prev, to: status)
            SoundManager.shared.sessionStatusTransition(from: prev, to: status)
        case .sessionExit(let id, _, _):
            let prev = sessionStatus[id]
            if let i = sessions.firstIndex(where: { $0.id == id }) {
                sessions[i].alive = false
                sessions[i].status = .dead
            }
            sessionStatus[id] = .dead
            HapticManager.shared.sessionStatusTransition(from: prev, to: .dead)
            SoundManager.shared.sessionStatusTransition(from: prev, to: .dead)
        case .sessionCreated(let s):
            if !sessions.contains(where: { $0.id == s.id }) {
                sessions.append(s)
            }
            sessionStatus[s.id] = s.status
            // Light tap when a new session pops in (often PM-driven). No sound —
            // session-spawn is a frequent event during PM coordination and
            // adding sound here would feel chatty.
            HapticManager.shared.light()
        case .sessionKilled(let id):
            // Remove from the visible list entirely. Mac semantics for kill
            // were "leave a dead row so the user can restart from the terminal
            // banner" — but the phone has no restart UI, so the user
            // reasonably expects "kill = gone." Matches the renderer's own
            // handleKill which also filters the session out of state.
            sessions.removeAll { $0.id == id }
            sessionStatus[id] = nil
            sessionData[id] = nil
        case .sessionMeta(let s):
            if let i = sessions.firstIndex(where: { $0.id == s.id }) {
                sessions[i] = s
            } else {
                sessions.append(s)
            }
        case .scheduleFired:
            Task { await self.refreshSchedules() }
        case .scheduleChanged(let s):
            if let i = schedules.firstIndex(where: { $0.id == s.id }) {
                schedules[i] = s
            } else {
                schedules.append(s)
            }
        case .bye(let reason):
            lastError = "Server: \(reason)"
        case .groupsChanged:
            Task { await self.refreshGroups() }
        case .unknown:
            break
        }
    }

    private func waitForConnection(timeout: Double = 5) async {
        let start = Date()
        while connectionState != .connected && Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if case .failed = connectionState { break }
        }
    }
}
