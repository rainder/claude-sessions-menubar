import Foundation
import SwiftUI

/// Polls the local claude-sessions server and every enabled remote in
/// servers.yaml on a fixed cadence. Lives at the App scope so polling
/// continues regardless of whether the popover is open.
@MainActor
final class SessionsStore: ObservableObject {
    @Published private(set) var local = HostState(name: "local", loading: true)
    @Published private(set) var remotes: [HostState] = []

    private let interval: TimeInterval
    private var pollTask: Task<Void, Never>?

    /// Keys ("host:pid") of sessions that were already in a waiting state on
    /// the previous tick. Used to fire notifications only on *transitions*
    /// into waiting — not for every tick that finds a session still waiting.
    private var prevWaitingKeys: Set<String> = []
    /// Suppresses notifications on the very first tick so we don't spam the
    /// user with one popup per currently-waiting session at app launch.
    private var transitionTrackingPrimed = false

    init(interval: TimeInterval = 2) {
        self.interval = interval
        start()
    }

    deinit {
        pollTask?.cancel()
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: UInt64((self?.interval ?? 2) * 1_000_000_000))
            }
        }
    }

    func refresh() {
        Task { await tick() }
    }

    /// Worst-case across local + remotes — drives the menubar glyph.
    var worstStatus: SessionStatus {
        var worst: SessionStatus = .idle
        if local.worstStatus > worst { worst = local.worstStatus }
        for r in remotes where r.worstStatus > worst { worst = r.worstStatus }
        return worst
    }

    /// Total session count across all hosts (used for the summary line).
    var totalSessions: Int {
        local.sessions.count + remotes.reduce(0) { $0 + $1.sessions.count }
    }

    private func tick() async {
        let cfgs = (try? ServersConfig.load()) ?? []
        let enabled = cfgs.filter { $0.enable }

        // Preserve prior state per server-name so a slow host's row keeps its
        // last known sessions while a new fetch is in flight. Same pattern as
        // the Go RemoteHub.
        let prevByName = Dictionary(uniqueKeysWithValues: remotes.map { ($0.name, $0) })
        let placeholders: [HostState] = enabled.map { cfg in
            if var prev = prevByName[cfg.name] {
                prev.loading = true
                return prev
            }
            return HostState(name: cfg.name, loading: true)
        }
        self.remotes = placeholders

        async let localResult: HostState = fetchLocal()
        async let remoteResults: [HostState] = withTaskGroup(of: (Int, HostState).self) { group in
            for (i, cfg) in enabled.enumerated() {
                group.addTask { (i, await Self.fetchOne(cfg)) }
            }
            var results = Array(repeating: HostState(name: ""), count: enabled.count)
            for await (i, state) in group {
                results[i] = state
            }
            return results
        }

        self.local = await localResult
        self.remotes = await remoteResults

        detectWaitingTransitions()
    }

    /// Diffs the current waiting-session set against the previous tick and
    /// fires a notification for each *newly* waiting session. Identifiers
    /// are stable per (host, pid) so the same waiting state doesn't notify
    /// twice if it's still waiting on the next tick.
    private func detectWaitingTransitions() {
        struct Hit { let host: String; let session: Session }
        var hits: [Hit] = []
        for s in local.sessions where !s.waitingFor.isEmpty {
            hits.append(Hit(host: local.name, session: s))
        }
        for r in remotes {
            for s in r.sessions where !s.waitingFor.isEmpty {
                hits.append(Hit(host: r.name, session: s))
            }
        }
        let currKeys = Set(hits.map { "\($0.host):\($0.session.id)" })

        if transitionTrackingPrimed {
            let newly = currKeys.subtracting(prevWaitingKeys)
            for hit in hits where newly.contains("\(hit.host):\(hit.session.id)") {
                let title = hit.session.name.isEmpty
                    ? "session \(hit.session.pid)"
                    : hit.session.name
                NotificationManager.shared.notifyWaiting(
                    host: hit.host,
                    sessionTitle: title,
                    waitingFor: hit.session.waitingFor,
                    identifier: "claude-waiting-\(hit.host)-\(hit.session.id)"
                )
            }
        }
        prevWaitingKeys = currKeys
        transitionTrackingPrimed = true
    }

    private func fetchLocal() async -> HostState {
        var state = local
        state.loading = false
        state.error = nil
        do {
            let token = try SessionsClient.localToken()
            state.sessions = try await SessionsClient.fetch(host: "127.0.0.1", port: 8765, token: token)
        } catch {
            state.sessions = []
            state.error = "\(error)"
        }
        return state
    }

    private static func fetchOne(_ cfg: ServerConfig) async -> HostState {
        var state = HostState(name: cfg.name)
        do {
            state.sessions = try await SessionsClient.fetch(host: cfg.host, port: cfg.port, token: cfg.token)
        } catch {
            state.error = "\(error)"
        }
        return state
    }
}
