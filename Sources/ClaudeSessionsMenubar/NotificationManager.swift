import Foundation
import UserNotifications

/// Fires a macOS notification each time a session transitions from
/// not-waiting → waiting (e.g. idle → "waiting:permission"). The store
/// owns the transition detection; this is just the thin wrapper around
/// UNUserNotificationCenter so we can stub or disable it cleanly.
///
/// **Bundling caveat:** UNUserNotificationCenter requires a registered
/// bundle identifier. When this app runs via `swift run` without a
/// proper .app bundle, authorization will fail silently and no
/// notifications will fire. They work once the app is wrapped in an
/// .app bundle with a CFBundleIdentifier (a future packaging step).
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private(set) var authorized = false

    private init() {}

    func requestAuthorization() async {
        do {
            authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("notification auth failed: \(error.localizedDescription)")
            authorized = false
        }
    }

    func notifyWaiting(host: String, sessionTitle: String, waitingFor: String, identifier: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude needs you · \(host)"
        content.body = waitingFor.isEmpty
            ? sessionTitle
            : "\(sessionTitle) — \(waitingFor)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("notify deliver failed: \(error.localizedDescription)")
            }
        }
    }
}
