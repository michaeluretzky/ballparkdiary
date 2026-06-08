import Foundation
import Observation

/// Central app state. Owns the user's connected inboxes, the attended games
/// derived from them, the onboarding scan flow, and all derived statistics.
/// All tickets from every connected inbox are merged into a single diary so
/// stats always reflect the user's *combined* total.
///
/// Gmail inboxes are scanned for real: the user signs in with Google, we read
/// ticket-receipt emails (read-only), detect MLB matchups, and confirm each one
/// against the public MLB Stats API for the true final score. Other providers
/// and the cloud-preview fallback use a clearly-labelled demo scan.
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
    var scanError: String? = nil
    var foundEmails: [String] = []                      // subjects revealed during current scan
    var connectedInboxes: [ConnectedInbox] = []         // successfully connected inboxes
    var pendingInbox: ConnectedInbox? = nil             // inbox currently being scanned
    var favoriteTeamId: String = Team.yankees.id

    /// Attended games keyed by the inbox they were sourced from. The merged
    /// diary (`games`) is the union of every value, sorted newest-first.
    var gamesByInbox: [UUID: [AttendedGame]] = [:]

    private let defaults = UserDefaults.standard
    private let storageKey = "ballparkdiary.state.v1"

    init() {
        load()
    }

    /// Persisted choice of the user's home team. Used to pre-rotate the map
    /// and tint stats. Set during onboarding via `pickFavorite(_:)`.
    func pickFavorite(_ team: Team) {
        favoriteTeamId = team.id
        hasPickedFavorite = true
        save()
    }

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

    // MARK: Cool extras

    /// Games attended on this calendar day in previous years ("On this day").
    var onThisDayGames: [AttendedGame] {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.dateComponents([.month, .day], from: .now)
        return games.filter {
            let c = cal.dateComponents([.month, .day], from: $0.date)
            return c.month == today.month && c.day == today.day
        }
    }

    /// The user's "lucky charm" — their win rate when rooting for their
    /// favorite team across games they attended.
    var luckyCharm: (wins: Int, losses: Int, team: Team)? {
        let favorite = favoriteTeam
        let relevant = games.filter { $0.homeTeamId == favorite.id || $0.awayTeamId == favorite.id }
        guard !relevant.isEmpty else { return nil }
        let wins = relevant.filter { g in
            let favHome = g.homeTeamId == favorite.id
            let favWon = favHome ? g.homeScore > g.awayScore : g.awayScore > g.homeScore
            return favWon
        }.count
        return (wins, relevant.count - wins, favorite)
    }

    /// Ballparks the user has not yet visited, for the "30 Ballpark Quest".
    var ballparksRemaining: [Ballpark] {
        Ballpark.all.filter { !visitedBallparkIds.contains($0.id) }
    }

    // MARK: Inbox management

    func isProviderConnected(_ provider: InboxProvider) -> Bool {
        connectedInboxes.contains(where: { $0.provider == provider })
    }

    /// Begin connecting a new inbox. Gmail uses the real Google Sign-In + Gmail
    /// API pipeline when a client id is configured; everything else (and the
    /// cloud-preview fallback) uses the demo scan.
    func connect(provider: InboxProvider, email: String? = nil) {
        guard pendingInbox == nil else { return }
        if provider != .other, isProviderConnected(provider) { return }
        scanError = nil

        if provider == .gmail, GmailService.shared.isConfigured {
            startRealGmailScan()
            return
        }

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
        if inbox.provider == .gmail { GmailService.shared.signOut() }
        save()
    }

    // MARK: Manual entries

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
        save()
    }

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
        save()
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

    // MARK: - Real Gmail scan

    private func startRealGmailScan() {
        let placeholder = ConnectedInbox(
            id: UUID(),
            email: "Gmail",
            provider: .gmail,
            ticketsFound: 0,
            connectedAt: .now
        )
        pendingInbox = placeholder
        scanPhase = .connecting
        foundEmails = []

        Task { @MainActor in
            do {
                let account = try await GmailService.shared.signInAndAuthorize()
                pendingInbox?.email = account.email

                let messages = try await GmailService.shared.fetchTicketMessages(accessToken: account.accessToken)
                let detected = TicketEmailParser.detect(in: messages)

                if detected.isEmpty {
                    scanPhase = .scanning(progress: 0.4, currentSubject: "No baseball tickets found yet")
                    try? await Task.sleep(for: .milliseconds(700))
                }

                var built: [AttendedGame] = []
                let existingKeys = Set(games.map(dayParkKey))
                var batchKeys = Set<String>()
                let total = max(detected.count, 1)

                for (index, candidate) in detected.prefix(40).enumerated() {
                    scanPhase = .scanning(
                        progress: Double(index + 1) / Double(total),
                        currentSubject: candidate.subject
                    )
                    foundEmails.append(candidate.subject)
                    if let game = await buildGame(from: candidate) {
                        let key = dayParkKey(game)
                        if !existingKeys.contains(key), !batchKeys.contains(key) {
                            batchKeys.insert(key)
                            built.append(game)
                        }
                    }
                }

                scanPhase = .finishing
                try? await Task.sleep(for: .milliseconds(600))

                var saved = placeholder
                saved.email = account.email
                saved.ticketsFound = built.count
                gamesByInbox[saved.id] = built
                connectedInboxes.append(saved)
                pendingInbox = nil
                scanPhase = .finished
                save()

                try? await Task.sleep(for: .milliseconds(950))
                hasCompletedOnboarding = true
                scanPhase = .idle
                save()
            } catch {
                pendingInbox = nil
                scanPhase = .idle
                #if targetEnvironment(simulator)
                scanError = "Google blocks sign-in inside the preview simulator for security. Gmail connection works normally once you install the app on your iPhone via TestFlight."
                #else
                scanError = (error as? GmailError)?.errorDescription ?? "Couldn't connect to Gmail. Please try again."
                #endif
            }
        }
    }

    /// Resolve a detected ticket to a real, completed MLB game.
    private func buildGame(from candidate: DetectedGame) async -> AttendedGame? {
        for date in candidate.candidateDates.prefix(3) {
            guard let results = try? await MLBStatsService.shared.games(on: date, teamMlbId: candidate.teamMlbId) else {
                continue
            }
            let finals = results.filter { $0.isFinal }
            let match: MLBGameResult?
            if let opponent = candidate.opponentMlbId {
                match = finals.first {
                    ($0.homeMlbId == candidate.teamMlbId && $0.awayMlbId == opponent) ||
                    ($0.awayMlbId == candidate.teamMlbId && $0.homeMlbId == opponent)
                } ?? finals.first
            } else {
                match = finals.first
            }
            if let match {
                return AttendedGame.from(
                    result: match,
                    source: candidate.source,
                    emailSubject: candidate.subject,
                    favoriteTeamId: favoriteTeamId
                )
            }
        }
        return nil
    }

    private func dayParkKey(_ game: AttendedGame) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: game.date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(game.ballparkId)"
    }

    // MARK: - Demo scan (non-Gmail providers / preview fallback)

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
        save()

        try? await Task.sleep(for: .milliseconds(950))
        hasCompletedOnboarding = true
        scanPhase = .idle
        save()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var favoriteTeamId: String
        var hasPickedFavorite: Bool
        var hasCompletedOnboarding: Bool
        var hasAcceptedTerms: Bool
        var inboxes: [ConnectedInbox]
        var gamesByInbox: [String: [AttendedGame]]
    }

    private func save() {
        let snapshot = Snapshot(
            favoriteTeamId: favoriteTeamId,
            hasPickedFavorite: hasPickedFavorite,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasAcceptedTerms: hasAcceptedTerms,
            inboxes: connectedInboxes,
            gamesByInbox: Dictionary(uniqueKeysWithValues: gamesByInbox.map { ($0.key.uuidString, $0.value) })
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        favoriteTeamId = snapshot.favoriteTeamId
        hasPickedFavorite = snapshot.hasPickedFavorite
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        hasAcceptedTerms = snapshot.hasAcceptedTerms
        connectedInboxes = snapshot.inboxes
        gamesByInbox = Dictionary(uniqueKeysWithValues: snapshot.gamesByInbox.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }
}
