import Foundation

/// Owns the WebSocket connection to one Mac bridge. The store layer (BridgeStore)
/// drives this and translates events to @Published state for SwiftUI. We keep
/// the client a plain class isolated to a serial queue — actors trip up on
/// URLSessionWebSocketTask's delegate / completion handler model.
///
/// `@unchecked Sendable`: every mutable property is touched only on `queue`,
/// which gives us the same effective guarantee as an actor. We can't prove
/// that to the Swift 6 concurrency checker, so we assert it manually.
final class BridgeClient: @unchecked Sendable {
    typealias EventHandler = (BridgeEvent) -> Void

    private let server: ServerHandle
    private let token: String
    private let queue = DispatchQueue(label: "com.lomusciolabs.anthology-ios.bridge")
    private var task: URLSessionWebSocketTask?
    private var session: URLSession
    private var nextRequestId = 0
    private var pendingRequests: [String: CheckedContinuation<InboundMessage, Error>] = [:]
    private var heartbeatTimer: DispatchSourceTimer?
    private var reconnectAttempt = 0
    private var explicitlyDisconnected = false
    private var onEvent: EventHandler?
    private var connectionState: ConnectionState = .disconnected
    private var stateHandler: ((ConnectionState) -> Void)?

    init(server: ServerHandle, token: String) {
        self.server = server
        self.token = token
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 0  // long-lived
        self.session = URLSession(configuration: cfg)
    }

    var isConnected: Bool {
        queue.sync { connectionState == .connected }
    }

    func setEventHandler(_ handler: @escaping EventHandler) {
        queue.async { self.onEvent = handler }
    }

    func setStateHandler(_ handler: @escaping (ConnectionState) -> Void) {
        queue.async { self.stateHandler = handler }
    }

    // MARK: - Lifecycle

    func connect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.explicitlyDisconnected = false
            self.openSocket()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.explicitlyDisconnected = true
            self.heartbeatTimer?.cancel()
            self.heartbeatTimer = nil
            self.task?.cancel(with: .normalClosure, reason: nil)
            self.task = nil
            self.updateState(.disconnected)
        }
    }

    /// Tear down any stale socket and immediately reconnect. Used when the app
    /// returns to the foreground after being suspended — iOS sometimes leaves
    /// the URLSessionWebSocketTask in a half-dead state where receive() never
    /// completes, so neither the existing error path nor the heartbeat ever
    /// notices and the scheduleReconnect ladder never starts.
    ///
    /// Idempotent: a no-op if we're already cleanly connected and the heartbeat
    /// is alive, so foregrounding while online doesn't churn the socket.
    func forceReconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.explicitlyDisconnected else { return }
            // Already connected and healthy — let it be.
            if self.connectionState == .connected && self.task != nil { return }
            self.heartbeatTimer?.cancel()
            self.heartbeatTimer = nil
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            // Reset attempt counter so the backoff penalty from a stale ladder
            // doesn't delay a foreground-triggered reconnect by up to 30s.
            self.reconnectAttempt = 0
            self.openSocket()
        }
    }

    private func openSocket() {
        guard !explicitlyDisconnected else { return }
        updateState(.connecting)
        guard var comps = URLComponents() as URLComponents? else { return }
        comps.scheme = "ws"
        comps.host = server.host
        comps.port = server.port
        comps.path = "/ws"
        guard let url = comps.url else {
            updateState(.failed("invalid url"))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: req)
        self.task = task
        task.resume()
        receiveLoop()
        // Send hello + start heartbeat after the upgrade — the WS will silently
        // drop if auth fails; the receive loop will surface the error.
        Task { @MainActor in
            do {
                _ = try await self.send(type: "hello", payload: [
                    "clientName": .init("Anthology iOS"),
                    "clientVersion": .init(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"),
                    "platform": .init("ios"),
                ])
                self.queue.async { self.markConnected() }
            } catch {
                // Hello failure means auth/transport problem — let receiveLoop's
                // error path schedule a reconnect.
            }
        }
    }

    private func markConnected() {
        reconnectAttempt = 0
        updateState(.connected)
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { _ = try? await self.send(type: "ping", payload: [:]) }
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func scheduleReconnect() {
        guard !explicitlyDisconnected else { return }
        reconnectAttempt += 1
        // Exponential backoff capped at 30s. First retry at ~1s.
        let backoff = min(30.0, pow(2.0, Double(reconnectAttempt - 1)))
        updateState(.reconnecting(after: backoff))
        queue.asyncAfter(deadline: .now() + backoff) { [weak self] in
            guard let self else { return }
            guard !self.explicitlyDisconnected else { return }
            self.openSocket()
        }
    }

    private func receiveLoop() {
        guard let task = task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .failure(let err):
                    self.handleSocketError(err)
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleIncoming(text: text)
                    case .data(let data):
                        if let s = String(data: data, encoding: .utf8) {
                            self.handleIncoming(text: s)
                        }
                    @unknown default:
                        break
                    }
                    // Continue the loop
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleSocketError(_ err: Error) {
        // Fail any pending requests.
        for (_, cont) in pendingRequests {
            cont.resume(throwing: err)
        }
        pendingRequests.removeAll()
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        task = nil
        updateState(.disconnected)
        scheduleReconnect()
    }

    private func handleIncoming(text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(InboundMessage.self, from: data) else {
            return
        }

        // Request/response correlation
        if let id = msg.id, let cont = pendingRequests.removeValue(forKey: id) {
            if msg.type == "err" {
                let code = msg.string("code") ?? "internal"
                let message = msg.string("message") ?? "Unknown error"
                cont.resume(throwing: BridgeRequestError(code: code, message: message))
            } else {
                cont.resume(returning: msg)
            }
            return
        }

        // Server-pushed event
        let event = BridgeEvent(message: msg)
        if let h = onEvent { h(event) }
    }

    // MARK: - Send

    @discardableResult
    func send(type: String, payload: [String: AnyCodable]) async throws -> InboundMessage {
        let id = "r_" + String(format: "%x", abs(UUID().hashValue & 0x7fffffff))
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<InboundMessage, Error>) in
            queue.async {
                guard let task = self.task, self.connectionState != .disconnected else {
                    cont.resume(throwing: BridgeRequestError(code: "not_connected", message: "Not connected"))
                    return
                }
                let outbound = OutboundMessage(type: type, id: id, payload: payload)
                guard let data = try? outbound.jsonData(),
                      let text = String(data: data, encoding: .utf8) else {
                    cont.resume(throwing: BridgeRequestError(code: "encode_failed", message: "Could not encode message"))
                    return
                }
                self.pendingRequests[id] = cont
                task.send(.string(text)) { err in
                    if let err = err {
                        self.queue.async {
                            if let waiting = self.pendingRequests.removeValue(forKey: id) {
                                waiting.resume(throwing: err)
                            }
                        }
                    }
                }
                // Per-request timeout — we don't want a forever-hung continuation
                // when the server stops responding.
                self.queue.asyncAfter(deadline: .now() + 8) {
                    if let waiting = self.pendingRequests.removeValue(forKey: id) {
                        waiting.resume(throwing: BridgeRequestError(code: "timeout", message: "Request timed out"))
                    }
                }
            }
        }
    }

    /// Fire-and-forget variant for high-volume input where we don't care about
    /// per-keystroke ack latency.
    func sendOneWay(type: String, payload: [String: AnyCodable]) {
        queue.async {
            guard let task = self.task else { return }
            let outbound = OutboundMessage(type: type, id: nil, payload: payload)
            guard let data = try? outbound.jsonData(),
                  let text = String(data: data, encoding: .utf8) else { return }
            task.send(.string(text)) { _ in }
        }
    }

    // MARK: - State

    private func updateState(_ next: ConnectionState) {
        connectionState = next
        if let h = stateHandler {
            DispatchQueue.main.async { h(next) }
        }
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(after: Double)
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting(let s): return String(format: "Reconnecting in %.0fs", s)
        case .failed(let m): return "Failed: \(m)"
        }
    }
}

struct BridgeRequestError: Error, CustomStringConvertible {
    let code: String
    let message: String
    var description: String { "\(code): \(message)" }
}

/// High-level translation of incoming server events. Anything not recognized
/// is .unknown and gets forwarded for debug logging only.
enum BridgeEvent {
    case sessionData(sessionId: String, data: String)
    case sessionStatus(sessionId: String, status: SessionStatus)
    case sessionExit(sessionId: String, exitCode: Int?, signal: String?)
    case sessionCreated(SessionMeta)
    case sessionKilled(sessionId: String)
    case sessionMeta(SessionMeta)
    case scheduleFired(id: String, ok: Bool, error: String?)
    case scheduleChanged(Schedule)
    case bye(reason: String)
    case unknown(type: String)

    init(message: InboundMessage) {
        switch message.type {
        case "session_data":
            self = .sessionData(
                sessionId: message.string("sessionId") ?? "",
                data: message.string("data") ?? ""
            )
        case "session_status":
            let raw = message.string("status") ?? "idle"
            self = .sessionStatus(
                sessionId: message.string("sessionId") ?? "",
                status: SessionStatus(rawValue: raw) ?? .idle
            )
        case "session_exit":
            self = .sessionExit(
                sessionId: message.string("sessionId") ?? "",
                exitCode: message.int("exitCode"),
                signal: message.string("signal")
            )
        case "session_created":
            if let s: SessionMeta = message.value("session") {
                self = .sessionCreated(s)
            } else { self = .unknown(type: message.type) }
        case "session_killed":
            self = .sessionKilled(sessionId: message.string("sessionId") ?? "")
        case "session_meta":
            if let s: SessionMeta = message.value("session") {
                self = .sessionMeta(s)
            } else { self = .unknown(type: message.type) }
        case "schedule_fired":
            self = .scheduleFired(
                id: message.string("id") ?? "",
                ok: message.raw["ok"]?.boolValue ?? false,
                error: message.string("error")
            )
        case "schedule_changed":
            if let s: Schedule = message.value("schedule") {
                self = .scheduleChanged(s)
            } else { self = .unknown(type: message.type) }
        case "bye":
            self = .bye(reason: message.string("reason") ?? "")
        default:
            self = .unknown(type: message.type)
        }
    }
}
