import SwiftUI

struct SpawnView: View {
    @EnvironmentObject var store: BridgeStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cwd = "~"
    @State private var color = SessionConstants.colors.first ?? "#7B2FBE"
    @State private var tag: String = ""
    @State private var agentTool: String = "claude"
    @State private var personaName: String = ""    // bare worker name (no "worker-" prefix)
    @State private var pmMode: Bool = false
    @State private var selectedGroupId: String = ""
    @State private var runClaude = true
    @State private var submitting = false
    @State private var error: String?

    /// Tags recently used by any session on the Mac, newest-first, deduped, capped.
    /// Replaces the old fixed coding-only list — tag is now free-text with these
    /// as one-tap suggestions.
    private var recentTags: [String] {
        var seen: [String: Double] = [:]
        for s in store.sessions {
            guard let t = s.tag?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { continue }
            let ts = s.createdAt ?? 0
            if ts >= (seen[t] ?? 0) { seen[t] = ts }
        }
        return seen.sorted(by: { $0.value > $1.value }).prefix(10).map(\.key)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. fix login flow", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("/Users/you/code/project", text: $cwd)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if !store.recentDirs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(store.recentDirs, id: \.self) { dir in
                                    Button {
                                        cwd = dir
                                        HapticManager.shared.selection()
                                    } label: {
                                        Text(dir.split(separator: "/").last.map(String.init) ?? dir)
                                            .font(.caption.monospaced())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Working directory")
                } footer: {
                    Text("Claude runs in this directory. Path on the Mac, not on this phone.")
                }

                // -------------------- Agent picker --------------------
                Section {
                    Picker("Agent", selection: $agentTool) {
                        Text("Claude Code").tag("claude")
                        Text("OpenAI Codex").tag("codex")
                    }
                    .pickerStyle(.segmented)
                    .disabled(pmMode)  // PM mode is Claude-only in v1.
                } footer: {
                    if pmMode {
                        Text("Project Manager mode uses Claude — MCP-tools attach is Claude-specific.")
                    } else if agentTool == "codex" {
                        Text("Spawns `codex` on the Mac instead of `claude`. Codex CLI must be installed.")
                    } else {
                        Text("Spawns `claude` on the Mac in the chosen directory.")
                    }
                }

                // -------------------- Persona (workers) --------------------
                if !store.workers.isEmpty && !pmMode {
                    Section {
                        Picker("Persona", selection: $personaName) {
                            Text("— none —").tag("")
                            ForEach(groupedWorkers, id: \.category) { group in
                                Section(group.category.capitalized) {
                                    ForEach(group.workers) { w in
                                        Text("\(w.emoji ?? "🐝") \(w.name)").tag(w.name)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Persona (optional)")
                    } footer: {
                        Text("Spawns the session pre-loaded with this worker's system prompt.")
                    }
                }

                // -------------------- Project Manager --------------------
                Section {
                    Toggle(isOn: $pmMode.animation()) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Project Manager mode")
                                .font(.body.weight(.medium))
                            Text("Gives this session MCP tools to spawn / message / kill other sessions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: pmMode) { _, on in
                        if on {
                            personaName = ""
                            agentTool = "claude"
                            HapticManager.shared.medium()
                        }
                    }
                }

                // -------------------- Group --------------------
                if !store.groups.isEmpty {
                    Section {
                        Picker("Group", selection: $selectedGroupId) {
                            Text("— Ungrouped —").tag("")
                            ForEach(store.groups) { g in
                                Text(g.name).tag(g.id)
                            }
                        }
                    } header: {
                        Text("Folder")
                    } footer: {
                        Text("Sessions can be moved between groups later from the long-press menu.")
                    }
                }

                // -------------------- Color --------------------
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
                                .onTapGesture {
                                    color = hex
                                    HapticManager.shared.selection()
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // -------------------- Tag --------------------
                Section {
                    TextField("optional — e.g. cds-emails, marketing, research", text: $tag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !recentTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(recentTags, id: \.self) { t in
                                    Button {
                                        tag = (tag == t) ? "" : t
                                        HapticManager.shared.selection()
                                    } label: {
                                        Text(t)
                                            .font(.caption.monospaced())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                tag == t
                                                    ? Color.accentColor.opacity(0.25)
                                                    : Color.gray.opacity(0.12),
                                                in: Capsule()
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(tag == t
                                                        ? Color.accentColor
                                                        : Color.gray.opacity(0.4))
                                            )
                                            .foregroundStyle(tag == t ? Color.accentColor : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tag")
                } footer: {
                    Text("Any label — not just coding terms. Recently-used tags show up as quick-pick chips.")
                }

                if !pmMode {
                    Section {
                        Toggle("Run agent at start", isOn: $runClaude)
                    } footer: {
                        Text("Off launches a plain shell instead of the chosen agent.")
                    }
                }

                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.callout) }
                }
            }
            .navigationTitle("Spawn session")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await store.refreshRecentDirs()
                await store.refreshWorkers()
                await store.refreshGroups()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.light()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if submitting { ProgressView() } else { Text("Spawn") }
                    }
                    .disabled(!canSubmit || submitting)
                }
            }
        }
    }

    private struct WorkerGroup {
        let category: String
        let workers: [Worker]
    }

    private var groupedWorkers: [WorkerGroup] {
        let bucketed = Dictionary(grouping: store.workers) { $0.category }
        // Predictable category order so the picker doesn't reshuffle on refresh.
        let order = ["engineering", "design", "content", "analytics", "business", "research", "other"]
        return order.compactMap { cat in
            guard let list = bucketed[cat], !list.isEmpty else { return nil }
            return WorkerGroup(category: cat, workers: list.sorted { $0.name < $1.name })
        }
    }

    private var canSubmit: Bool {
        !cwd.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let resolvedName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? (pmMode ? "project manager" : (cwd.split(separator: "/").last.map(String.init) ?? "session"))
            : name.trimmingCharacters(in: .whitespaces)
        let session = await store.spawn(
            name: resolvedName,
            cwd: cwd,
            runClaude: pmMode ? true : runClaude,
            tag: tag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tag.trimmingCharacters(in: .whitespaces),
            color: color,
            pm: pmMode,
            agentTool: pmMode ? "claude" : agentTool,
            personaName: pmMode ? nil : (personaName.isEmpty ? nil : personaName),
            groupId: selectedGroupId.isEmpty ? nil : selectedGroupId
        )
        if session != nil {
            HapticManager.shared.success()
            SoundManager.shared.success()
            dismiss()
        } else {
            HapticManager.shared.error()
            error = store.lastError ?? "Spawn failed"
        }
    }
}
