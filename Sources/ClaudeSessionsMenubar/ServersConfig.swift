import Foundation

/// One entry under `servers:` in ~/.config/claude-sessions/servers.yaml.
/// Schema mirrors the Go claude-sessions ServerConfig — see yaml.go in the
/// parent repo for the canonical spec. Keep field semantics in sync.
struct ServerConfig: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var host: String
    var port: Int = 8765
    var token: String
    var sshHost: String? = nil
    var sshUser: String? = nil
    var enable: Bool = true
}

enum ServersConfig {
    static var path: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-sessions/servers.yaml")
    }

    /// Returns every entry, including disabled ones, so the settings UI can
    /// show toggles for them. The Go TUI filters at its own load step.
    static func load() throws -> [ServerConfig] {
        guard let data = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }
        return parse(data)
    }

    static func save(_ servers: [ServerConfig]) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try render(servers).write(to: path, atomically: true, encoding: .utf8)
    }

    /// Hand-rolled YAML reader for the exact shape claude-sessions defines.
    /// No flow style, no nested structures, no anchors. Mirrors yaml.go.
    static func parse(_ yaml: String) -> [ServerConfig] {
        var out: [ServerConfig] = []
        var current: ServerConfig? = nil
        var inServers = false

        for raw in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).replacingOccurrences(of: "\r", with: "")
            let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
            if stripped.isEmpty || stripped.hasPrefix("#") { continue }
            let indent = line.count - stripped.count

            if indent == 0, line.contains(":") {
                let key = line.split(separator: ":", maxSplits: 1).first
                    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                inServers = (key == "servers")
                continue
            }
            if !inServers { continue }

            if stripped.hasPrefix("- ") {
                if let c = current { out.append(c) }
                current = ServerConfig(name: "", host: "", token: "")
                let rest = String(stripped.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let (k, v) = splitKV(rest) {
                    set(&current!, key: k, value: v)
                }
                continue
            }
            if var c = current, let (k, v) = splitKV(String(stripped)) {
                set(&c, key: k, value: v)
                current = c
            }
        }
        if let c = current { out.append(c) }
        return out
    }

    /// Round-trips back to the canonical layout used by `claude-sessions -s`'s
    /// stderr snippet. Two-space indent, fields in a stable order.
    static func render(_ servers: [ServerConfig]) -> String {
        var out = "servers:\n"
        for s in servers {
            out += "  - name: \(s.name)\n"
            out += "    host: \(s.host)\n"
            out += "    port: \(s.port)\n"
            out += "    token: \(s.token)\n"
            if let h = s.sshHost { out += "    ssh_host: \(h)\n" }
            if let u = s.sshUser { out += "    ssh_user: \(u)\n" }
            if !s.enable { out += "    enable: false\n" }
        }
        return out
    }

    private static func splitKV(_ s: String) -> (String, String)? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let key = s[..<colon].trimmingCharacters(in: .whitespaces)
        var val = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if val.count >= 2 {
            let first = val.first, last = val.last
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                val = String(val.dropFirst().dropLast())
            }
        }
        return (key, val)
    }

    private static func set(_ c: inout ServerConfig, key: String, value: String) {
        switch key {
        case "name": c.name = value
        case "host": c.host = value
        case "port": if let n = Int(value) { c.port = n }
        case "token": c.token = value
        case "ssh_host": c.sshHost = value
        case "ssh_user": c.sshUser = value
        case "enable":
            switch value.lowercased() {
            case "false", "no", "off", "0": c.enable = false
            case "true", "yes", "on", "1": c.enable = true
            default: break
            }
        default: break
        }
    }
}
