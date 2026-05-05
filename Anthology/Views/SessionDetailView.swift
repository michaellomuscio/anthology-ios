import SwiftUI

struct SessionDetailView: View {
    let session: SessionMeta
    @EnvironmentObject var store: BridgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var keyboardVisible = false
    @State private var showActions = false
    @State private var promptText = ""
    @State private var showPrompt = false
    @State private var confirmingKill = false
    @State private var killing = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TerminalContainerView(sessionId: session.id)
                .background(Color.black)
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showPrompt = true
                    } label: {
                        Label("Send prompt…", systemImage: "text.cursor")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingKill = true
                    } label: {
                        Label("Kill session", systemImage: "stop.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Send prompt", isPresented: $showPrompt) {
            TextField("Prompt", text: $promptText)
            Button("Send") {
                Task {
                    await store.sendPrompt(promptText, to: session.id)
                    promptText = ""
                }
            }
            Button("Cancel", role: .cancel) { promptText = "" }
        } message: {
            Text("Sends the text as if typed and Enter pressed.")
        }
        .alert("Kill session?", isPresented: $confirmingKill) {
            Button("Kill", role: .destructive) {
                killing = true
                Task {
                    await store.kill(sessionId: session.id)
                    killing = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Terminates the Claude process for \"\(session.name)\". The session row stays in the list with a dead status so you can restart from the Mac.")
        }
        .overlay {
            if killing {
                Color.black.opacity(0.4)
                    .overlay(ProgressView("Killing…").tint(.white).foregroundStyle(.white).padding())
                    .ignoresSafeArea()
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            StatusDot(status: store.sessionStatus[session.id] ?? session.status, size: 8)
            Text((store.sessionStatus[session.id] ?? session.status).label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
            Text(session.cwd)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }
}
