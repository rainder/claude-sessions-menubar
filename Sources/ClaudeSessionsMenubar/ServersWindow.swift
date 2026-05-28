import SwiftUI

/// Add / remove / edit / toggle servers, written back to servers.yaml.
/// Sibling to claude-sessions' TUI — both read and write the same file, so
/// changes here are picked up by the TUI on its next 2s tick (and vice versa).
struct ServersWindow: View {
    @StateObject private var editor = ServersEditor()
    @TerminalPreference private var preferredTerminal: Terminal

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Servers").font(.title2).bold()
                Spacer()
                if editor.dirty {
                    Text("unsaved changes").font(.caption).foregroundStyle(.orange)
                }
                Button("Add Server") { editor.addEmpty() }
                Button("Save") { editor.save() }
                    .keyboardShortcut("s")
                    .disabled(!editor.dirty)
            }
            .padding()

            Divider()

            if editor.rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($editor.rows) { $row in
                            ServerEditorRow(
                                row: $row,
                                onChange: { editor.markDirty() },
                                onRemove: { editor.remove(id: row.id) }
                            )
                            Divider()
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("Open TUI in:").font(.subheadline)
                Picker("Terminal", selection: $preferredTerminal) {
                    ForEach(Terminal.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 160)
                Spacer()
                Text("\(editor.rows.count) configured").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 360)
        .task { editor.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No servers yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start `claude-sessions -s` on a remote host and add it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add Server") { editor.addEmpty() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct ServerEditorRow: View {
    @Binding var row: ServersEditor.Row
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: $row.config.enable)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: row.config.enable) { _ in onChange() }
                TextField("name", text: $row.config.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .onChange(of: row.config.name) { _ in onChange() }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                TextField("host (IP or DNS)", text: $row.config.host)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: row.config.host) { _ in onChange() }
                TextField("port", value: $row.config.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onChange(of: row.config.port) { _ in onChange() }
            }

            TextField("token", text: $row.config.token)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: row.config.token) { _ in onChange() }

            HStack {
                TextField("ssh_host (optional)", text: optionalBinding(\.sshHost))
                    .textFieldStyle(.roundedBorder)
                TextField("ssh_user (optional)", text: optionalBinding(\.sshUser))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// String binding that maps "" ↔ nil so empty inputs are written as
    /// "field absent" rather than the literal empty string.
    private func optionalBinding(_ keyPath: WritableKeyPath<ServerConfig, String?>) -> Binding<String> {
        Binding(
            get: { row.config[keyPath: keyPath] ?? "" },
            set: {
                row.config[keyPath: keyPath] = $0.isEmpty ? nil : $0
                onChange()
            }
        )
    }
}

@MainActor
final class ServersEditor: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var config: ServerConfig
    }

    @Published var rows: [Row] = []
    @Published var dirty: Bool = false

    func load() {
        let cfgs = (try? ServersConfig.load()) ?? []
        rows = cfgs.map { Row(config: $0) }
        dirty = false
    }

    func save() {
        do {
            try ServersConfig.save(rows.map(\.config))
            dirty = false
        } catch {
            // Surface this in the UI once we add a status field; for now,
            // failing silently leaves dirty=true so the user can retry.
            NSLog("save failed: \(error)")
        }
    }

    func addEmpty() {
        rows.append(Row(config: ServerConfig(name: "new-server", host: "", token: "")))
        dirty = true
    }

    func remove(id: UUID) {
        rows.removeAll { $0.id == id }
        dirty = true
    }

    func markDirty() { dirty = true }
}
