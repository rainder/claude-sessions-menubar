# claude-sessions-menubar

macOS menubar companion for [claude-sessions](https://github.com/rainder/claude-sessions). Reads the same `~/.config/claude-sessions/servers.yaml` as the TUI, polls each server's `/sessions` endpoint, and surfaces aggregate status in the menubar plus a popover with per-server breakdown.

## Status

Functional but unbundled. Works when run via `swift run`:

- Menubar icon shifts shape with the worst session status across all hosts (idle / busy / waiting).
- Popover shows one row per host (local + every enabled remote) with colored status dot and `N waiting · N busy · N idle` breakdown.
- **Open TUI** button launches your preferred terminal (Terminal.app, iTerm, Ghostty — settable in the Manage window).
- **Manage…** opens a separate window for add/remove/edit/toggle with full `servers.yaml` round-trip (including `enable: false`).
- **Notifications** fire when a session transitions into `waiting:permission`. Requires the app to be packaged as a proper `.app` bundle with a `CFBundleIdentifier`; under `swift run` authorization fails silently and notifications won't appear.

Not yet built: proper `.app` bundle + signing + DMG for distribution; per-server "Open TUI scoped to host"; on-screen overlay (the WireGuard-style menubar-and-popover covers the core flow already).

## Build / run

Requires macOS 13+ and Swift 5.9+ (ships with Xcode 15 or Command Line Tools).

```sh
swift run
```

Hides from Dock automatically via `NSApp.setActivationPolicy(.accessory)` — no Info.plist needed during development. A proper `.app` bundle with `LSUIElement=YES` and signing comes later, when we're closer to distribution.

## Layout

```
Sources/ClaudeSessionsMenubar/
  App.swift             MenuBarExtra entry point + AppDelegate
  ServersConfig.swift   ~/.config/claude-sessions/servers.yaml read/write
```

## Relationship to claude-sessions

This app does **not** reimplement session collection. It consumes the HTTP server (`claude-sessions -s`) running locally on `127.0.0.1:8765`, which gives us local + every remote in one feed. The local `claude-sessions -s` needs to be running (launchctl autostart recommended).

`servers.yaml` is shared state; this app is a GUI editor + watcher for the same file the TUI reads. The `enable: false` field acts as the WireGuard-style row toggle.

## License

MIT.
