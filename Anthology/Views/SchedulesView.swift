import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject var store: BridgeStore
    @State private var editing: Schedule?
    @State private var showingNew = false

    var body: some View {
        Group {
            if store.schedules.isEmpty {
                ContentUnavailableView(
                    "No schedules yet",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Tap + to create one — runs at a cron interval or a single specific time.")
                )
            } else {
                List {
                    ForEach(store.schedules) { schedule in
                        Button { editing = schedule } label: { row(for: schedule) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await store.deleteSchedule(id: schedule.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Task { await store.runScheduleNow(id: schedule.id) }
                                } label: {
                                    Label("Run", systemImage: "play.fill")
                                }
                                .tint(.green)
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { await store.refreshSchedules() }
        .refreshable { await store.refreshSchedules() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { sch in
            ScheduleEditorView(initial: sch)
        }
        .sheet(isPresented: $showingNew) {
            ScheduleEditorView(initial: nil)
        }
    }

    private func row(for s: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color(hex: s.color))
                    .frame(width: 4, height: 18)
                    .clipShape(Capsule())
                Text(s.name).font(.body.weight(.medium)).lineLimit(1)
                if !s.tag.isEmpty {
                    Text(s.tag)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color(hex: s.color).opacity(0.2), in: Capsule())
                        .foregroundStyle(Color(hex: s.color))
                }
                Spacer()
                if !s.enabled {
                    Text("paused")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text(scheduleSummary(s))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !s.prompt.isEmpty {
                Text(s.prompt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func scheduleSummary(_ s: Schedule) -> String {
        if s.kind == "cron", let c = s.cron, !c.isEmpty {
            if let next = s.nextRunAt {
                return "cron \(c)  ·  next \(formatRelative(next))"
            }
            return "cron \(c)"
        }
        if s.kind == "oneshot", let w = s.when, !w.isEmpty {
            return "one-shot \(w)"
        }
        return s.kind
    }

    private func formatRelative(_ epochMs: Double) -> String {
        let d = Date(timeIntervalSince1970: epochMs / 1000.0)
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
