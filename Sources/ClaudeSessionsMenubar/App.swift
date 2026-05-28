import SwiftUI
import AppKit

@main
struct ClaudeSessionsMenubarApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "person.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Equivalent to LSUIElement=YES in Info.plist, but works for SPM-built
    // executables that don't ship a bundle. Hides from Dock + Cmd-Tab.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct ContentView: View {
    @State private var servers: [ServerConfig] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Sessions")
                .font(.headline)
            Divider()
            if servers.isEmpty {
                Text("No servers configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(servers) { s in
                    HStack {
                        Image(systemName: s.enable ? "circle.fill" : "circle")
                            .foregroundStyle(s.enable ? .green : .secondary)
                            .font(.system(size: 8))
                        Text(s.name)
                        Spacer()
                        Text("\(s.host):\(s.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack {
                Button("Manage Servers…") {
                    // TODO: open a Window scene for add/remove/edit
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 280, height: 220)
        .task { reload() }
    }

    private func reload() {
        servers = (try? ServersConfig.load()) ?? []
    }
}
