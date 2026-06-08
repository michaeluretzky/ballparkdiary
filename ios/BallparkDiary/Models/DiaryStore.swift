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

    /// Personal forwarding token + resolved address for the TripIt-style
    /// ticket-forwarding pipeline. The user forwards receipts to this address;
    /// the backend parses them and we import confirmed games.
    var forwardingToken: String = ""
    var forwardingAddress: String? = nil
    var forwardingConfigured: Bool = false
    var isRefreshingForwarding: Bool = false
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
        if forwardingToken.isEmpty {
            forwardingToken = Self.makeToken()
            save()
        }
    }

    /// A URL-safe, email-local-part-safe token (matches the backend's
    /// `^[a-z0-9]{8,40}$` validation).
    private static func makeToken() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<16).map { _ in alphabet.randomElement() ?? "a" })
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

    // MARK: - Forwarded ticket import

    /// The email address users forward ticket receipts to, once the backend
    /// inbound domain is configured.
    var forwardingAddressDisplay: String {
        forwardingAddress ?? "\(forwardingToken)@…"
    }

    @discardableResult
    private func ensureForwardingInbox() -> ConnectedInbox {
        if let existing = connectedInboxes.first(where: { $0.provider == .forwarding }) {
            return existing
        }
        let inbox = ConnectedInbox(
            id: UUID(),
            email: "Forwarded tickets",
            provider: .forwarding,
            ticketsFound: 0,
            connectedAt: .now
        )
        connectedInboxes.append(inbox)
        return inbox
    }

    /// Resolve the forwarding address and import any newly-forwarded tickets,
    /// confirming each against the real MLB schedule before adding it.
    func refreshForwarding() async {
        guard ForwardingService.shared.isBackendConfigured, !isRefreshingForwarding else { return }
        isRefreshingForwarding = true
        defer { isRefreshingForwarding = false }

        if let registration = try? await ForwardingService.shared.register(token: forwardingToken) {
            forwardingConfigured = registration.configured
            forwardingAddress = registration.address
        }

        guard
            let candidates = try? await ForwardingService.shared.pending(token: forwardingToken),
            !candidates.isEmpty
        else { return }

        let inbox = ensureForwardingInbox()
        var existing = gamesByInbox[inbox.id] ?? []
        let existingKeys = Set(games.map(dayParkKey))
        var batchKeys = Set<String>()
        var processedIds: [String] = []

        for candidate in candidates {
            processedIds.append(candidate.id)
            guard let game = await buildGame(from: candidate.detectedGame) else { continue }
            let key = dayParkKey(game)
            guard !existingKeys.contains(key), !batchKeys.contains(key) else { continue }
            batchKeys.insert(key)
            existing.append(game)
        }

        gamesByInbox[inbox.id] = existing.sorted { $0.date > $1.date }
        if let idx = connectedInboxes.firstIndex(where: { $0.id == inbox.id }) {
            connectedInboxes[idx].ticketsFound = existing.count
        }
        save()

        await ForwardingService.shared.acknowledge(token: forwardingToken, ids: processedIds)
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

    // MARK: - Shared ticket import (Share Extension)

    @discardableResult
    private func ensureSharedInbox() -> ConnectedInbox {
        if let existing = connectedInboxes.first(where: { $0.provider == .shared }) {
            return existing
        }
        let inbox = ConnectedInbox(
            id: UUID(),
            email: "Shared tickets",
            provider: .shared,
            ticketsFound: 0,
            connectedAt: .now
        )
        connectedInboxes.append(inbox)
        return inbox
    }

    /// Drain tickets the user shared into the app via the Share Extension.
    /// Each shared item is parsed for an MLB matchup and confirmed against the
    /// real schedule before being added — all on-device, no email access.
    /// Returns the number of newly imported games.
    @discardableResult
    func importSharedTickets() async -> Int {
        let pending = SharedTicketStore.load()
        guard !pending.isEmpty else { return 0 }

        let messages = pending.map { payload in
            EmailMessage(
                id: payload.id,
                subject: payload.sourceHint,
                from: payload.sourceHint,
                snippet: payload.text,
                internalDate: payload.receivedAt
            )
        }
        let detected = TicketEmailParser.detect(in: messages)

        let inbox = ensureSharedInbox()
        var existing = gamesByInbox[inbox.id] ?? []
        let existingKeys = Set(games.map(dayParkKey))
        var batchKeys = Set<String>()
        var added = 0

        for candidate in detected {
            guard let game = await buildGame(from: candidate) else { continue }
            let key = dayParkKey(game)
            guard !existingKeys.contains(key), !batchKeys.contains(key) else { continue }
            batchKeys.insert(key)
            existing.append(game)
            added += 1
        }

        // Always clear the queue so the same shares aren't reprocessed, even if
        // a matchup couldn't be confirmed.
        SharedTicketStore.remove(ids: Set(pending.map(\.id)))

        guard added > 0 else { return 0 }
        gamesByInbox[inbox.id] = existing.sorted { $0.date > $1.date }
        if let idx = connectedInboxes.firstIndex(where: { $0.id == inbox.id }) {
            connectedInboxes[idx].ticketsFound = existing.count
        }
        if !hasCompletedOnboarding { hasCompletedOnboarding = true }
        save()
        return added
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
        var forwardingToken: String?
    }

    private func save() {
        let snapshot = Snapshot(
            favoriteTeamId: favoriteTeamId,
            hasPickedFavorite: hasPickedFavorite,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasAcceptedTerms: hasAcceptedTerms,
            inboxes: connectedInboxes,
            gamesByInbox: Dictionary(uniqueKeysWithValues: gamesByInbox.map { ($0.key.uuidString, $0.value) }),
            forwardingToken: forwardingToken.isEmpty ? nil : forwardingToken
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
        forwardingToken = snapshot.forwardingToken ?? ""
        gamesByInbox = Dictionary(uniqueKeysWithValues: snapshot.gamesByInbox.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }
}
