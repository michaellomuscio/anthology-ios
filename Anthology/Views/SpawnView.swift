import SwiftUI

struct SpawnView: View {
    @EnvironmentObject var store: BridgeStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cwd = "~"
    @State private var color = SessionConstants.colors.first ?? "#7B2FBE"
    @State private var tag: String = SessionConstants.tags.first ?? "feature"
    @State private var runClaude = true
    @State private var submitting = false
    @State private var error: String?

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
                            Button {
                                tag = t
                            } label: {
                                Text(t)
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        tag == t
                                            ? Color.accentColor.opacity(0.25)
                                            : Color.clear,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(tag == t ? Color.accentColor : Color.gray.opacity(0.4))
                                    )
                                    .foregroundStyle(tag == t ? Color.accentColor : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Run Claude", isOn: $runClaude)
                } footer: {
                    Text("Off launches a plain shell instead of `claude`.")
                }

                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.callout) }
                }
            }
            .navigationTitle("Spawn session")
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.refreshRecentDirs() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
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

    private var canSubmit: Bool {
        !cwd.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let resolvedName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? (cwd.split(separator: "/").last.map(String.init) ?? "session")
            : name.trimmingCharacters(in: .whitespaces)
        let session = await store.spawn(name: resolvedName, cwd: cwd, runClaude: runClaude)
        if session != nil {
            dismiss()
        } else {
            error = store.lastError ?? "Spawn failed"
        }
    }
}
