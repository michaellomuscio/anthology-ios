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
        await refreshSessions()
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

    func spawn(name: String, cwd: String, runClaude: Bool = true) async -> SessionMeta? {
        guard let c = client else { return nil }
        do {
            let ack = try await c.send(type: "spawn", payload: [
                "name": .init(name),
                "cwd": .init(cwd),
                "runClaude": .init(runClaude),
            ])
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
            sessionStatus[id] = status
            if let i = sessions.firstIndex(where: { $0.id == id }) {
                sessions[i].status = status
            }
        case .sessionExit(let id, _, _):
            if let i = sessions.firstIndex(where: { $0.id == id }) {
                sessions[i].alive = false
                sessions[i].status = .dead
            }
            sessionStatus[id] = .dead
        case .sessionCreated(let s):
            if !sessions.contains(where: { $0.id == s.id }) {
                sessions.append(s)
            }
            sessionStatus[s.id] = s.status
        case .sessionKilled(let id):
            if let i = sessions.firstIndex(where: { $0.id == id }) {
                sessions[i].alive = false
                sessions[i].status = .dead
            }
            sessionStatus[id] = .dead
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
