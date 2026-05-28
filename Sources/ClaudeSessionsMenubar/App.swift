import SwiftUI
import AppKit

@main
struct ClaudeSessionsMenubarApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = SessionsStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(counts: store.counts)
        }
        .menuBarExtraStyle(.window)

        // Separate Window scene for add/remove/edit/toggle, opened from the
        // popover via @Environment(\.openWindow). Not shown by default.
        Window("Servers", id: "servers") {
            ServersWindow()
                .environmentObject(store)
        }
        .defaultSize(width: 600, height: 420)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigusr1Source: DispatchSourceSignal?

    // Equivalent to LSUIElement=YES in Info.plist, but works for SPM-built
    // executables that don't ship a bundle. Hides from Dock + Cmd-Tab.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await NotificationManager.shared.requestAuthorization() }
        installTestSignalHandler()
    }

    /// `kill -USR1 <pid>` shows a synthetic Clippy prompt. Handy for tuning
    /// the overlay's look without producing a real waiting session.
    private func installTestSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler {
            Task { @MainActor in OverlayController.shared.showTestPrompt() }
        }
        src.resume()
        sigusr1Source = src
    }
}

/// The menubar label: per-state count badges so you can see at a glance
/// "1 waiting, 3 idle" without opening the popover. Each non-zero bucket
/// gets a shape (not just color) so the signal survives template-image
/// rendering on monochrome menubars. Buckets are ordered by urgency:
/// waiting (loud) → busy (neutral) → idle (dim).
struct MenuBarLabel: View {
    let counts: SessionCounts

    var body: some View {
        HStack(spacing: 4) {
            if counts.total == 0 {
                Image(systemName: "person")
                    .foregroundStyle(.secondary)
            }
            if counts.waiting > 0 {
                bucket(symbol: "exclamationmark.circle.fill", count: counts.waiting)
                    .foregroundStyle(.red)
            }
            if counts.busy > 0 {
                bucket(symbol: "circle.fill", count: counts.busy)
                    .imageScale(.small)
            }
            if counts.idle > 0 {
                bucket(symbol: "circle", count: counts.idle)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bucket(symbol: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
            Text("\(count)")
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: SessionsStore
    @Environment(\.openWindow) private var openWindow
    @TerminalPreference private var preferredTerminal: Terminal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claude Sessions").font(.headline)
                Spacer()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()

            HostRow(state: store.local, isLocal: true)
            ForEach(store.remotes) { state in
                HostRow(state: state, isLocal: false)
            }

            Spacer(minLength: 4)
            HStack {
                Button("Open TUI") { TUILauncher.openTUI(in: preferredTerminal) }
                    .keyboardShortcut(.return)
                Button("Refresh") { store.refresh() }
                Button("Manage…") { openWindow(id: "servers") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 340, height: max(200, CGFloat(140 + 28 * (1 + store.remotes.count))))
    }

    private var summary: String {
        let n = store.totalSessions
        return n == 1 ? "1 session" : "\(n) sessions"
    }
}

private struct HostRow: View {
    let state: HostState
    let isLocal: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            statusDot
            Text(state.name)
                .font(.body)
                .foregroundStyle(isLocal ? .primary : .primary)
            Spacer()
            detail
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var statusDot: some View {
        let color: Color = {
            if state.error != nil { return .gray }
            switch state.worstStatus {
            case .waiting: return .red
            case .busy:    return .yellow
            case .idle:    return .green
            }
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var detail: some View {
        if let err = state.error {
            if isLocal, err.contains("server not running") || err.contains("no token") {
                Text("local server not running")
            } else {
                Text(err)
            }
        } else if state.sessions.isEmpty && state.loading {
            Text("loading…")
        } else if state.sessions.isEmpty {
            Text("no sessions")
        } else {
            Text(counts)
        }
    }

    /// "3 idle · 1 waiting · 2 busy" — only includes non-zero buckets.
    private var counts: String {
        var waiting = 0, busy = 0, idle = 0
        for s in state.sessions {
            if !s.waitingFor.isEmpty { waiting += 1 }
            else if s.status == "busy" { busy += 1 }
            else { idle += 1 }
        }
        var parts: [String] = []
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if busy > 0    { parts.append("\(busy) busy") }
        if idle > 0    { parts.append("\(idle) idle") }
        return parts.joined(separator: " · ")
    }
}
