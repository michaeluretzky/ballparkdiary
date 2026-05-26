import Foundation
import Observation

/// Central app state. Owns the user's connected inboxes, the attended games
/// derived from them, the onboarding scan flow, and all derived statistics.
/// All tickets from every connected inbox are merged into a single diary so
/// stats always reflect the user's *combined* total.
@Observable
final class DiaryStore {
    enum ScanPhase: Equatable {
        case idle
        case connecting
        case scanning(progress: Double, currentSubject: String)
        case finishing
        case finished
    }

    var hasPickedFavorite: Bool = false
    var hasAcceptedTerms: Bool = false
    var hasCompletedOnboarding: Bool = false
    var scanPhase: ScanPhase = .idle
    var foundEmails: [String] = []                      // subjects revealed during current scan
    var connectedInboxes: [ConnectedInbox] = []         // successfully connected inboxes
    var pendingInbox: ConnectedInbox? = nil             // inbox currently being scanned
    var favoriteTeamId: String = Team.yankees.id

    /// Persisted choice of the user's home team. Used to pre-rotate the map
    /// and tint stats. Set during onboarding via `pickFavorite(_:)`.
    func pickFavorite(_ team: Team) {
        favoriteTeamId = team.id
        hasPickedFavorite = true
    }

    /// Attended games keyed by the inbox they were sourced from. The merged
    /// diary (`games`) is the union of every value, sorted newest-first.
    var gamesByInbox: [UUID: [AttendedGame]] = [:]

    // MARK: Derived state

    var games: [AttendedGame] {
        gamesByInbox.values.flatMap { $0 }.sorted { $0.date > $1.date }
    }

    /// Displayed in the scan UI — current pending inbox, or most recently connected.
    var connectedInbox: String? {
        pendingInbox?.email ?? connectedInboxes.last?.email
    }

    var visitedBallparkIds: Set<String> { Set(games.map(\.ballparkId)) }
    var ballparkCount: Int { visitedBallparkIds.count }
    var totalGames: Int { games.count }
    var totalRuns: Int { games.reduce(0) { $0 + $1.totalRuns } }
    var winCount: Int { games.filter(\.userWon).count }
    var lossCount: Int { games.count - winCount }
    var winPct: Double {
        guard !games.isEmpty else { return 0 }
        return Double(winCount) / Double(games.count)
    }

    var homeRunsWitnessed: Int {
        games.flatMap(\.highlights).filter { $0.kind == .homeRun || $0.kind == .walkoff }.count
    }

    var favoriteTeam: Team { Team.by(id: favoriteTeamId) ?? .yankees }

    /// Most-visited ballpark, if any.
    var homeBallpark: Ballpark? {
        let counts = Dictionary(grouping: games, by: \.ballparkId).mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return Ballpark.by(id: top.key)
    }

    /// Most-watched opponent, if any.
    var mostSeenOpponent: (team: Team, count: Int)? {
        var seen: [String: Int] = [:]
        for g in games {
            let opp = g.userRootedForHome ? g.awayTeamId : g.homeTeamId
            seen[opp, default: 0] += 1
        }
        guard let top = seen.max(by: { $0.value < $1.value }), let team = Team.by(id: top.key) else { return nil }
        return (team, top.value)
    }

    var longestStreak: Int {
        let chrono = games.sorted { $0.date < $1.date }
        var best = 0, run = 0
        for g in chrono { if g.userWon { run += 1; best = max(best, run) } else { run = 0 } }
        return best
    }

    // MARK: Inbox management

    func isProviderConnected(_ provider: InboxProvider) -> Bool {
        connectedInboxes.contains(where: { $0.provider == provider })
    }

    /// Begin connecting a new inbox and stream the mock scan. Safe to call
    /// during onboarding (first inbox) or from inside the app (additional ones);
    /// in both cases the scan animates against `scanPhase`.
    func connect(provider: InboxProvider, email: String? = nil) {
        guard pendingInbox == nil else { return }
        if provider != .other, isProviderConnected(provider) { return }
        let resolvedEmail = email ?? "you@\(provider.domain)"
        let inbox = ConnectedInbox(
            id: UUID(),
            email: resolvedEmail,
            provider: provider,
            ticketsFound: 0,
            connectedAt: .now
        )
        pendingInbox = inbox
        scanPhase = .connecting
        foundEmails = []
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            await streamScan(for: inbox)
        }
    }

    /// Remove a connected inbox and its attributed games. The combined diary
    /// automatically updates.
    func disconnect(_ inbox: ConnectedInbox) {
        gamesByInbox.removeValue(forKey: inbox.id)
        connectedInboxes.removeAll { $0.id == inbox.id }
    }

    // MARK: Manual entries

    /// Append a user-entered game (for ballparks visited before digital
    /// ticketing existed, or any game not surfaced by an inbox scan). Manual
    /// games are stored under a single synthetic "Manual entries" inbox so the
    /// running totals always include them.
    func addManualGame(_ game: AttendedGame) {
        let inbox = ensureManualInbox()
        var existing = gamesByInbox[inbox.id] ?? []
        existing.append(game)
        gamesByInbox[inbox.id] = existing
        if let idx = connectedInboxes.firstIndex(where: { $0.id == inbox.id }) {
            connectedInboxes[idx].ticketsFound = existing.count
        }
        if !hasCompletedOnboarding {
            hasCompletedOnboarding = true
        }
    }

    /// Remove a single manually-entered game by id.
    func removeManualGame(_ id: UUID) {
        guard let inbox = connectedInboxes.first(where: { $0.provider == .manual }) else { return }
        var existing = gamesByInbox[inbox.id] ?? []
        existing.removeAll { $0.id == id }
        if existing.isEmpty {
            gamesByInbox.removeValue(forKey: inbox.id)
            connectedInboxes.removeAll { $0.id == inbox.id }
        } else {
            gamesByInbox[inbox.id] = existing
            if let idx = connectedInboxes.firstIndex(where: { $0.id == inbox.id }) {
                connectedInboxes[idx].ticketsFound = existing.count
            }
        }
    }

    @discardableResult
    private func ensureManualInbox() -> ConnectedInbox {
        if let existing = connectedInboxes.first(where: { $0.provider == .manual }) {
            return existing
        }
        let inbox = ConnectedInbox(
            id: UUID(),
            email: "Manual entries",
            provider: .manual,
            ticketsFound: 0,
            connectedAt: .now
        )
        connectedInboxes.append(inbox)
        return inbox
    }

    @MainActor
    private func streamScan(for inbox: ConnectedInbox) async {
        let newGames = MockData.games(for: inbox.provider)
        let subjects = MockData.subjects(for: inbox.provider)
        let total = max(subjects.count, 1)
        for (i, subject) in subjects.enumerated() {
            try? await Task.sleep(for: .milliseconds(220))
            let progress = Double(i + 1) / Double(total)
            scanPhase = .scanning(progress: progress, currentSubject: subject)
            foundEmails.append(subject)
        }
        scanPhase = .finishing
        try? await Task.sleep(for: .milliseconds(700))

        var saved = inbox
        saved.ticketsFound = newGames.count
        gamesByInbox[saved.id] = newGames
        connectedInboxes.append(saved)
        pendingInbox = nil
        scanPhase = .finished

        try? await Task.sleep(for: .milliseconds(950))
        hasCompletedOnboarding = true
        scanPhase = .idle
    }
}
