import AppKit
import SwiftUI

/// One waiting session that Clippy is currently showing. Matches the same
/// "host:pid" identifier used by the notifications path so we can dismiss
/// Clippy when the underlying session leaves the waiting state.
struct WaitingPrompt: Identifiable, Equatable {
    let id: String     // "<host>:<pid>"
    let host: String
    let sessionTitle: String
    let waitingFor: String
}

/// Manages the floating overlay window ("Clippy") that pops up when a session
/// needs the user's attention. Singleton so SessionsStore can call into it
/// from its transition-detection path without holding a reference.
///
/// Reactive only: no recurring or proactive surfacing. Shown on idle→waiting
/// transitions, hidden the moment the same session is no longer waiting (user
/// responded, or session died). Disabling via the "clippyEnabled" UserDefault
/// makes showIfEnabled a no-op.
@MainActor
final class OverlayController: ObservableObject {
    static let shared = OverlayController()

    @Published var pending: WaitingPrompt? = nil
    private var window: NSPanel?

    /// Per-prompt snooze. Key is "host:pid"; value is the Date until which
    /// Clippy stays silent for that key. Cleared when the snooze elapses or
    /// when the prompt naturally exits the waiting state.
    private var snoozedUntil: [String: Date] = [:]

    private init() {}

    private var enabled: Bool {
        // Defaults to true. Read fresh each call so toggling in Settings takes
        // effect immediately without restart.
        UserDefaults.standard.object(forKey: "clippyEnabled") as? Bool ?? true
    }

    func showIfEnabled(_ prompt: WaitingPrompt) {
        guard enabled else {
            NSLog("[overlay] showIfEnabled: disabled in defaults, ignoring")
            return
        }
        if let until = snoozedUntil[prompt.id], until > Date() {
            NSLog("[overlay] showIfEnabled: snoozed until \(until)")
            return
        }
        pending = prompt
        ensureWindow()
        window?.orderFrontRegardless()
        NSLog("[overlay] shown id=\(prompt.id) visible=\(window?.isVisible == true) frame=\(window?.frame ?? .zero)")
    }

    /// Suppresses showIfEnabled for `prompt.id` for the given duration.
    /// `.infinity` means "until the session leaves the waiting state on its
    /// own" — the dismiss path below clears the entry.
    func snooze(_ id: String, for seconds: TimeInterval) {
        snoozedUntil[id] = Date().addingTimeInterval(seconds)
        dismissIfMatches(id)
    }

    /// Debug helper: fires a synthetic prompt so the overlay can be eyeballed
    /// without waiting for a real session to hit waiting:permission. Wired
    /// to SIGUSR1 in AppDelegate so it can be triggered from a shell with
    /// `kill -USR1 <pid>`.
    func showTestPrompt() {
        showIfEnabled(WaitingPrompt(
            id: "test:\(Int.random(in: 1...100000))",
            host: "preview",
            sessionTitle: "aero-doc-flow",
            waitingFor: "permission prompt"
        ))
    }

    /// Hides the overlay if and only if the pending prompt matches the given
    /// id. Avoids racing dismiss across rapid transition cycles.
    func dismissIfMatches(_ id: String) {
        if pending?.id == id { dismiss() }
    }

    func dismiss() {
        pending = nil
        window?.orderOut(nil)
    }

    private func ensureWindow() {
        if window != nil { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // .statusBar floats above normal windows but below the system
        // menubar. Combined with .fullScreenAuxiliary the panel stays on
        // top even over fullscreen apps; .canJoinAllSpaces makes it
        // follow the user across Mission Control spaces.
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Hosting view: hardcode the frame to match the panel's content
        // rect. `panel.contentLayoutRect` returns weird values on a newly-
        // created borderless panel before it's positioned. Autoresizing
        // keeps the hosting view in step if we ever resize.
        let hosting = NSHostingView(rootView: ClippyView(controller: self))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 140)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        position(panel)
        window = panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let w: CGFloat = 380, h: CGFloat = 140, pad: CGFloat = 24
        panel.setFrame(
            NSRect(x: area.maxX - w - pad, y: area.minY + pad, width: w, height: h),
            display: true
        )
    }
}
