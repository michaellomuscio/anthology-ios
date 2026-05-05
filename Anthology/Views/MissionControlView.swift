import SwiftUI

/// Grid of session tiles. While visible, subscribes to all session_data so
/// each tile shows a live tail of recent output.
struct MissionControlView: View {
    @EnvironmentObject var store: BridgeStore

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 14)]

    var body: some View {
        ScrollView {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Tap the + button to spawn one.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.sessions) { session in
                        NavigationLink(value: session) {
                            tile(for: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
        .task {
            await store.subscribeAll()
            await store.refreshSessions()
        }
        .onDisappear { store.unsubscribeAll() }
    }

    private func tile(for session: SessionMeta) -> some View {
        let status = store.sessionStatus[session.id] ?? session.status
        let preview = lastLines(of: store.sessionData[session.id] ?? "", count: 6)

        return VStack(spacing: 0) {
            // Color stripe + header row
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color(hex: session.color))
                    .frame(width: 4, height: 18)
                    .clipShape(Capsule())
                Text(session.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                StatusDot(status: status, size: 8)
                Text(status.label)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Output preview
            Text(preview.isEmpty ? "—" : preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .lineLimit(6)
                .truncationMode(.head)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.4))

            // Footer
            HStack(spacing: 6) {
                if let tag = session.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(hex: session.color).opacity(0.2), in: Capsule())
                        .foregroundStyle(Color(hex: session.color))
                }
                Text(session.cwd)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
        )
    }

    /// Strip ANSI escapes and grab the last N lines of plain text. Cheap-and-cheerful
    /// for tile previews — full fidelity is in SessionDetailView.
    private func lastLines(of raw: String, count: Int) -> String {
        let stripped = stripANSI(raw)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(count)
        return tail.joined(separator: "\n")
    }

    private func stripANSI(_ s: String) -> String {
        // Match CSI sequences (ESC [ ... letter) plus OSC and a few common 2-byte
        // escapes. Coarse but sufficient for the tile preview.
        let patterns = [
            "\u{1B}\\[[0-?]*[ -/]*[@-~]",
            "\u{1B}\\][^\u{07}]*\u{07}",
            "\u{1B}[\\(\\)\\*\\+][A-Za-z0-9]",
            "\u{1B}[=>78]",
        ]
        var out = s
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(out.startIndex..., in: out)
                out = re.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
        }
        // Carriage returns confuse line splitting; collapse \r\n and drop bare \r
        out = out.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "\r", with: "")
        return out
    }
}
