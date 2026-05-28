# claude-sessions-menubar

macOS menubar companion for [claude-sessions](https://github.com/rainder/claude-sessions). Reads the same `~/.config/claude-sessions/servers.yaml` as the TUI, polls each server's `/sessions` endpoint, and surfaces aggregate status in the menubar plus a popover with per-server breakdown.

## Status

Skeleton. The `MenuBarExtra` icon renders, the popover lists configured servers, and the YAML parser round-trips. Not yet built: `/sessions` polling, the manage-servers window, notifications for `waiting:permission`, "open TUI" terminal launcher.

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
