import SwiftUI

struct ScheduleEditorView: View {
    let initial: Schedule?
    @EnvironmentObject var store: BridgeStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cwd = "~"
    @State private var prompt = ""
    @State private var color = SessionConstants.colors.first ?? "#7B2FBE"
    @State private var tag = SessionConstants.tags.first ?? "feature"
    @State private var kind: String = "cron"
    @State private var cron: String = "0 9 * * *"
    @State private var when: Date = Date().addingTimeInterval(3600)
    @State private var enabled = true
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. daily standup", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("Kind", selection: $kind) {
                        Text("Cron").tag("cron")
                        Text("One-shot").tag("oneshot")
                    }
                    .pickerStyle(.segmented)

                    if kind == "cron" {
                        TextField("0 9 * * *", text: $cron)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    } else {
                        DatePicker("Run at", selection: $when, in: Date()...)
                    }
                } header: {
                    Text("When")
                } footer: {
                    if kind == "cron" {
                        Text("Standard 5-field cron: minute, hour, day-of-month, month, day-of-week.")
                    }
                }

                Section {
                    TextField("/Users/you/code/project", text: $cwd)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if !store.recentDirs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(store.recentDirs, id: \.self) { d in
                                    Button { cwd = d } label: {
                                        Text(d.split(separator: "/").last.map(String.init) ?? d)
                                            .font(.caption.monospaced())
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: { Text("Working directory") }

                Section {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 100)
                        .font(.body.monospaced())
                } header: {
                    Text("Prompt")
                } footer: {
                    Text("Sent into the session as if typed and Enter pressed. Leave blank to spawn an empty session.")
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36))], spacing: 10) {
                        ForEach(SessionConstants.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: hex == color ? 2 : 0)
                                        .padding(2)
                                )
                                .onTapGesture { color = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Tag") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(SessionConstants.tags, id: \.self) { t in
                            Button { tag = t } label: {
                                Text(t)
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(tag == t ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
                                    .overlay(Capsule().stroke(tag == t ? Color.accentColor : Color.gray.opacity(0.4)))
                                    .foregroundStyle(tag == t ? Color.accentColor : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Enabled", isOn: $enabled)
                }

                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.callout) }
                }
            }
            .navigationTitle(initial == nil ? "New schedule" : "Edit schedule")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let s = initial { populate(from: s) }
                await store.refreshRecentDirs()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if submitting { ProgressView() } else { Text("Save") }
                    }
                    .disabled(!canSave || submitting)
                }
            }
        }
    }

    private var canSave: Bool {
        !cwd.trimmingCharacters(in: .whitespaces).isEmpty
            && (kind != "cron" || !cron.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func populate(from s: Schedule) {
        name = s.name
        cwd = s.cwd
        prompt = s.prompt
        color = s.color
        tag = s.tag
        kind = s.kind
        cron = s.cron ?? "0 9 * * *"
        if let w = s.when {
            let f = ISO8601DateFormatter()
            when = f.date(from: w) ?? Date().addingTimeInterval(3600)
        }
        enabled = s.enabled
    }

    private func save() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let f = ISO8601DateFormatter()
        let s = Schedule(
            id: initial?.id ?? "sch_\(UUID().uuidString.prefix(10).lowercased())",
            name: name.isEmpty ? "schedule" : name,
            cwd: cwd,
            prompt: prompt,
            color: color,
            tag: tag,
            kind: kind,
            cron: kind == "cron" ? cron : nil,
            when: kind == "oneshot" ? f.string(from: when) : nil,
            enabled: enabled,
            createdAt: initial?.createdAt ?? Date().timeIntervalSince1970 * 1000,
            lastRunAt: initial?.lastRunAt,
            nextRunAt: nil
        )
        if await store.upsertSchedule(s) != nil {
            dismiss()
        } else {
            error = store.lastError ?? "Save failed"
        }
    }
}
