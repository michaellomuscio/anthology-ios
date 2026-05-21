import SwiftUI
import UIKit
import SwiftTerm

/// SwiftUI wrapper around SwiftTerm's TerminalView. Subscribes the BridgeStore
/// to the given session, replays the buffer snapshot, and forwards new bytes
/// as they arrive. Forwards user keystrokes to the bridge via send_input.
struct TerminalContainerView: UIViewRepresentable {
    let sessionId: String
    @EnvironmentObject var store: BridgeStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, sessionId: sessionId)
    }

    func makeUIView(context: Context) -> TerminalView {
        let term = TerminalView()
        term.translatesAutoresizingMaskIntoConstraints = false
        term.terminalDelegate = context.coordinator
        // Defaults: 80x24 grid, scaled by SwiftTerm to fit the available size.
        term.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        term.backgroundColor = .black
        term.nativeBackgroundColor = .black
        context.coordinator.term = term
        // Kick off the bridge subscription. Replay the snapshot, then live data
        // arrives via the @Published observation in the coordinator.
        Task { @MainActor in
            if let snapshot = await store.subscribe(to: sessionId) {
                term.feed(text: snapshot)
            }
            context.coordinator.startObserving()
        }
        return term
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // No-op — coordinator handles the live stream.
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.stopObserving()
        coordinator.store.unsubscribe(from: coordinator.sessionId)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let store: BridgeStore
        let sessionId: String
        weak var term: TerminalView?
        private var lastSeenLength = 0
        private var observation: Task<Void, Never>?

        init(store: BridgeStore, sessionId: String) {
            self.store = store
            self.sessionId = sessionId
        }

        @MainActor
        func startObserving() {
            // Initialize replay cursor to the snapshot we already fed.
            lastSeenLength = store.sessionData[sessionId]?.count ?? 0
            // Poll the @Published store for incremental data. The store is on
            // MainActor, so this is safe. A change publisher would be more
            // idiomatic but the polling cost (every ~50ms during input) is
            // negligible compared with terminal rendering.
            observation = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let buf = self.store.sessionData[self.sessionId] ?? ""
                    if buf.count > self.lastSeenLength {
                        let new = String(buf.suffix(buf.count - self.lastSeenLength))
                        self.term?.feed(text: new)
                        self.lastSeenLength = buf.count
                    } else if buf.count < self.lastSeenLength {
                        // Buffer was truncated by the cap — replay the new tail.
                        self.term?.feed(text: buf)
                        self.lastSeenLength = buf.count
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
            }
        }

        func stopObserving() {
            observation?.cancel()
            observation = nil
        }

        // MARK: TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            // SwiftTerm hands us raw bytes from the keyboard / pasteboard.
            // Delegate methods always fire on the main thread; assumeIsolated
            // keeps input latency low (no Task hop) while satisfying the
            // BridgeStore @MainActor isolation requirement.
            guard let str = String(bytes: data, encoding: .utf8) else { return }
            MainActor.assumeIsolated {
                store.sendInput(str, to: sessionId)
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            // Intentionally NOT calling store.resize. The Mac renderer is the
            // authoritative source of PTY dimensions — when iOS also resized,
            // the PTY size bounced between the two and Claude's TUI tables /
            // box-drawing lines redrew mid-stream at different widths, leaving
            // both views looking mangled. iOS now displays whatever the Mac
            // set; SwiftTerm handles soft-wrapping of lines wider than the
            // visible area.
        }

        func setTerminalTitle(source: TerminalView, title: String) { /* ignore */ }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { /* ignore */ }
        func scrolled(source: TerminalView, position: Double) { /* ignore */ }
        func clipboardCopy(source: TerminalView, content: Data) {
            if let s = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = s
            }
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) { /* ignore */ }
        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
            if let url = URL(string: link), ["http", "https", "mailto"].contains(url.scheme) {
                UIApplication.shared.open(url)
            }
        }
    }
}
