import Foundation

/// One Claude session as exposed by `claude-sessions -s`'s `/sessions` endpoint.
/// Field names match the Go schema (see session.go in the parent repo).
struct Session: Decodable, Identifiable, Hashable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let status: String
    let waitingFor: String
    let updatedAt: Int64
    let name: String
    let version: String
    let cpu: String
    let tmux: String

    var id: String { String(pid) }

    /// "waiting:permission prompt" etc. — mirrors Go StatusDisplay().
    var statusDisplay: String {
        waitingFor.isEmpty ? status : "\(status):\(waitingFor)"
    }
}

/// One server's most recent fetch outcome — what the popover renders per row.
struct HostState: Identifiable {
    let name: String
    var loading: Bool = false
    var sessions: [Session] = []
    var error: String? = nil

    var id: String { name }

    /// "Worst" status priority for the menubar glyph: waiting > busy > anything else.
    var worstStatus: SessionStatus {
        for s in sessions {
            if !s.waitingFor.isEmpty { return .waiting }
        }
        for s in sessions {
            if s.status == "busy" { return .busy }
        }
        return .idle
    }
}

enum SessionStatus: Int, Comparable {
    case idle = 0, busy = 1, waiting = 2
    static func < (lhs: SessionStatus, rhs: SessionStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Aggregate counts shown in the menubar (and reused in popover summaries).
struct SessionCounts {
    var waiting: Int = 0
    var busy: Int = 0
    var idle: Int = 0

    var total: Int { waiting + busy + idle }

    mutating func bump(_ s: Session) {
        if !s.waitingFor.isEmpty { waiting += 1 }
        else if s.status == "busy" { busy += 1 }
        else { idle += 1 }
    }
}

enum ClientError: Error, CustomStringConvertible {
    case noLocalToken
    case connectionRefused
    case timeout
    case badStatus(Int)
    case other(String)

    var description: String {
        switch self {
        case .noLocalToken:
            return "no token at ~/.config/claude-sessions/server-token (is `claude-sessions -s` ever started?)"
        case .connectionRefused:
            return "connection refused (server not running)"
        case .timeout:
            return "timed out"
        case .badStatus(let code):
            return "HTTP \(code)"
        case .other(let s):
            return s
        }
    }
}

enum SessionsClient {
    /// Hits `/sessions` on a single host. Throws on any failure (caller wraps
    /// per-host so one bad host doesn't poison the rest).
    static func fetch(host: String, port: Int, token: String, timeout: TimeInterval = 5) async throws -> [Session] {
        guard let url = URL(string: "http://\(host):\(port)/sessions") else {
            throw ClientError.other("bad url for \(host):\(port)")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let err as URLError {
            switch err.code {
            case .cannotConnectToHost, .cannotFindHost: throw ClientError.connectionRefused
            case .timedOut:                              throw ClientError.timeout
            default:                                     throw ClientError.other(err.localizedDescription)
            }
        }

        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw ClientError.badStatus(http.statusCode)
        }

        struct Envelope: Decodable { let sessions: [Session] }
        return (try JSONDecoder().decode(Envelope.self, from: data)).sessions
    }

    /// Reads the auto-generated bearer token that `claude-sessions -s` writes
    /// on first start (mode 0600). Used for the local 127.0.0.1 fetch since
    /// localhost doesn't appear in servers.yaml.
    static func localToken() throws -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-sessions/server-token")
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else {
            throw ClientError.noLocalToken
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
