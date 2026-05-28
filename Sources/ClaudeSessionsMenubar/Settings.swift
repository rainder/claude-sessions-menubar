import Foundation
import SwiftUI

/// User preferences persisted via UserDefaults. Keep this small — the
/// authoritative server config lives in servers.yaml, not here.
enum Terminal: String, CaseIterable, Identifiable {
    case terminalApp = "Terminal.app"
    case iterm       = "iTerm"
    case ghostty     = "Ghostty"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// AppleScript that opens a new terminal window and runs claude-sessions.
    /// Not every terminal exposes a stable AppleScript surface — for the ones
    /// that do, we use it; for others (Ghostty), we fall back to launching
    /// the app and letting the user type the command.
    func openCommandScript(_ command: String) -> String {
        switch self {
        case .terminalApp:
            return """
            tell application "Terminal"
                do script "\(command)"
                activate
            end tell
            """
        case .iterm:
            return """
            tell application "iTerm"
                create window with default profile
                tell current session of current window to write text "\(command)"
                activate
            end tell
            """
        case .ghostty:
            // Ghostty doesn't expose a stable AppleScript "do script". Best
            // we can do without piping through stdin tricks: open it and
            // let the user type. Worth replacing once Ghostty grows the
            // surface.
            return """
            tell application "Ghostty" to activate
            """
        }
    }
}

@propertyWrapper
struct TerminalPreference: DynamicProperty {
    @AppStorage("preferredTerminal") private var raw: String = Terminal.terminalApp.rawValue

    var wrappedValue: Terminal {
        get { Terminal(rawValue: raw) ?? .terminalApp }
        nonmutating set { raw = newValue.rawValue }
    }

    var projectedValue: Binding<Terminal> {
        Binding(
            get: { Terminal(rawValue: raw) ?? .terminalApp },
            set: { raw = $0.rawValue }
        )
    }
}

enum TUILauncher {
    /// Spawns the user's preferred terminal and runs `claude-sessions` in it.
    /// `claude-sessions` is expected on PATH (typically ~/.local/bin via the
    /// installer). Errors are swallowed silently — the worst case is no
    /// terminal opens, which the user notices immediately.
    static func openTUI(in terminal: Terminal) {
        let script = terminal.openCommandScript("claude-sessions")
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }
}
