import Foundation
import Observation

/// Central app state. Owns the user's diary of attended games, sourced from two
/// places only — tickets the user shares into the app (Share Extension) and
/// games added by hand. All games are merged into a single diary so stats always
/// reflect the user's combined total.
///
/// Shared tickets are read on-device (OCR / PDF / text), the MLB matchup is
/// detected locally, and each one is confirmed against the public MLB Stats API
/// for the true final score (or kept as an upcoming game when it hasn't been
/// played yet). No email access, no accounts, no servers.
@Observable
@MainActor
final class DiaryStore {
    var hasPickedFavorite: Bool = false
    var hasAcceptedTerms: Bool = false
    var hasCompletedOnboarding: Bool = false

    /// True while a shared-ticket import / score refresh is running.
    var isRefreshing: Bool = false

    var favoriteTeamId: String = Team.yankees.id

    /// Attended games keyed by the source they came from (shared tickets or
    /// manual entries). The merged diary (`games`) is the union of every value.
    var gamesByInbox: [UUID: [AttendedGame]] = [:]

    /// Successfully connected sources (shown in the Inboxes tab).
    var connectedInboxes: [ConnectedInbox] = []

    /// Games that couldn't be confirmed and were dropped — surfaced to user.
    var droppedCandidates: [DroppedCandidate] = []

    /// Non-nil when a deep-link requests a tab switch. Observed by MainTabsView.
    var requestedTab: String? = nil

    /// Local retry tracking for shared ticket payloads (in-memory only).
    private var importAttempts: [String: (count: Int, firstSeen: Date)] = [:]

    /// When the last full refresh completed. Used to throttle the refresh that
    /// fires on every foreground / scene activation so we don't hammer the MLB
    /// Stats API (each refresh can walk every game and issue many requests).
    private var lastRefreshAt: Date?
    /// Minimum gap between non-forced refreshes.
    private static let refreshThrottle: TimeInterval = 60

    private let defaults = UserDefaults.standard
    private let storageKey = "ballparkdiary.state.v2"

    /// Max failed import attempts before dropping a payload.
    private static let maxImportAttempts = 5
    /// Max days a payload can sit unconfirmed before dropping.
    private static let maxImportAgeDays = 7

    init() {
        load()
        collapseDuplicates()
    }

    /// Persisted choice of the user's home team. Used to pre-rotate the map
    /// and tint stats. Set during onboarding via `pickFavorite(_:)`.
    func pickFavorite(_ team: Team) {
        favoriteTeamId = team.id
        hasPickedFavorite = true
        save()
    }

    /// Finish onboarding and enter the main app.
    func completeOnboarding() {
        hasCompletedOnboarding = true
        save()
    }

    // MARK: Derived state

    /// Every game, newest first.
    var games: [AttendedGame] {
        gamesByInbox.values.flatMap { $0 }.sorted { $0.date > $1.date }
    }

    /// Games that have been played (real final score) — the basis for all stats.
    var completedGames: [AttendedGame] {
        games.filter { !$0.isUpcoming }
    }

    /// Tickets for games that haven't happened yet, soonest first.
    var upcomingGames: [AttendedGame] {
        games.filter(\.isUpcoming).sorted { $0.date < $1.date }
    }

    var visitedBallparkIds: Set<String> { Set(completedGames.map(\.ballparkId)) }
    var ballparkCount: Int { visitedBallparkIds.count }
    var totalGames: Int { completedGames.count }
    var totalRuns: Int { completedGames.reduce(0) { $0 + $1.totalRuns } }
    var winCount: Int { completedGames.filter(\.userWon).count }
    var lossCount: Int { completedGames.count - winCount }
    var winPct: Double {
        guard !completedGames.isEmpty else { return 0 }
        return Double(winCount) / Double(completedGames.count)
    }

    var homeRunsWitnessed: Int {
        completedGames.flatMap(\.highlights).filter { $0.kind == .homeRun || $0.kind == .walkoff }.count
    }

    var favoriteTeam: Team { Team.by(id: favoriteTeamId) ?? .yankees }

    /// Most-visited ballpark, if any.
    var homeBallpark: Ballpark? {
        let counts = Dictionary(grouping: completedGames, by: \.ballparkId).mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return Ballpark.by(id: top.key)
    }

    /// Most-watched opponent, if any.
    var mostSeenOpponent: (team: Team, count: Int)? {
        var seen: [String: Int] = [:]
        for g in completedGames {
            let opp = g.userRootedForHome ? g.awayTeamId : g.homeTeamId
            seen[opp, default: 0] += 1
        }
        guard let top = seen.max(by: { $0.value < $1.value }), let team = Team.by(id: top.key) else { return nil }
        return (team, top.value)
    }

    var longestStreak: Int {
        let chrono = completedGames.sorted { $0.date < $1.date }
        var best = 0, run = 0
        for g in chrono { if g.userWon { run += 1; best = max(best, run) } else { run = 0 } }
        return best
    }

    // MARK: Cool extras

    /// Games attended on this calendar day in previous years ("On this day").
    var onThisDayGames: [AttendedGame] {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.dateComponents([.month, .day], from: .now)
        return completedGames.filter {
            let c = cal.dateComponents([.month, .day], from: $0.date)
            return c.month == today.month && c.day == today.day
        }
    }

    /// The user's "lucky charm" — their win rate when rooting for their
    /// favorite team across games they attended.
    var luckyCharm: (wins: Int, losses: Int, team: Team)? {
        let favorite = favoriteTeam
        let relevant = completedGames.filter { $0.homeTeamId == favorite.id || $0.awayTeamId == favorite.id }
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

    // MARK: - Canonical identity

    /// Calendar day + home team + away team uniquely identifies a game.
    /// Used for dedup across shared imports and manual entries.
    private func canonicalKey(_ game: AttendedGame) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: game.date)
        let ids = [game.homeTeamId, game.awayTeamId].sorted().joined(separator: "-")
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(ids)"
    }

    /// Check whether a game with this identity already exists in the diary.
    func hasGame(day: Date, homeTeamId: String, awayTeamId: String) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: day)
        let ids = [homeTeamId, awayTeamId].sorted().joined(separator: "-")
        let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(ids)"
        return games.contains { canonicalKey($0) == key }
    }

    // MARK: Manual entries

    /// Add a manually entered game. Rejects duplicates by canonical key.
    /// Returns nil if a game with the same day + teams already exists.
    @discardableResult
    func addManualGame(_ game: AttendedGame) -> AttendedGame? {
        let key = canonicalKey(game)
        let existingKeys = Set(games.map(canonicalKey))
        guard !existingKeys.contains(key) else { return nil }

        let inbox = ensureInbox(.manual, label: "Manual entries")
        var existing = gamesByInbox[inbox.id] ?? []
        existing.append(game)
        gamesByInbox[inbox.id] = existing.sorted { $0.date > $1.date }
        if let idx = connectedInboxes.firstIndex(where: { $0.id == inbox.id }) {
            connectedInboxes[idx].ticketsFound = existing.count
        }
        if !hasCompletedOnboarding { hasCompletedOnboarding = true }
        save()
        return game
    }

    /// Delete a single game by ID regardless of source (shared or manual).
    /// Updates the owning inbox's ticket count.
    func deleteGame(_ id: UUID) {
        for (inboxId, list) in gamesByInbox {
            if list.contains(where: { $0.id == id }) {
                var updated = list.filter { $0.id != id }
                if updated.isEmpty {
                    gamesByInbox.removeValue(forKey: inboxId)
                    connectedInboxes.removeAll { $0.id == inboxId }
                } else {
                    gamesByInbox[inboxId] = updated
                    if let idx = connectedInboxes.firstIndex(where: { $0.id == inboxId }) {
                        connectedInboxes[idx].ticketsFound = updated.count
                    }
                }
                save()
                return
            }
        }
    }

    /// Remove a source and its attributed games.
    func disconnect(_ inbox: ConnectedInbox) {
        gamesByInbox.removeValue(forKey: inbox.id)
        connectedInboxes.removeAll { $0.id == inbox.id }
        save()
    }

    @discardableResult
    private func ensureInbox(_ provider: InboxProvider, label: String) -> ConnectedInbox {
        if let existing = connectedInboxes.first(where: { $0.provider == provider }) {
            return existing
        }
        let inbox = ConnectedInbox(
            id: UUID(),
            email: label,
            provider: provider,
            ticketsFound: 0,
            connectedAt: .now
        )
        connectedInboxes.append(inbox)
        return inbox
    }

    // MARK: - Refresh (pull-to-refresh)

    /// Import any newly-shared tickets and refresh upcoming games whose final
    /// score may now be available. Also re-verifies unverified manual games.
    /// Returns the number of newly imported games.
    ///
    /// Non-forced calls are throttled: foregrounding the app repeatedly (or the
    /// scene re-activating) won't re-run the full network sweep more than once a
    /// minute. Pass `force: true` for user-initiated pulls and the share-import
    /// deep link, where an immediate refresh is expected.
    @discardableResult
    func refresh(force: Bool = false) async -> Int {
        guard !isRefreshing else { return 0 }
        if !force, let last = lastRefreshAt, Date.now.timeIntervalSince(last) < Self.refreshThrottle {
            return 0
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = .now
        }

        let imported = await importSharedTickets()
        await refreshUpcomingScores()
        await enrichExistingGames()
        await reVerifyUnverifiedGames()
        return imported
    }

    // MARK: - Shared ticket import (Share Extension)

    /// Drain tickets the user shared into the app via the Share Extension. Each
    /// shared item is parsed for an MLB matchup and confirmed against the real
    /// schedule before being added — all on-device. A game with a future first
    /// pitch is added as `.upcoming` (no score yet); a finished game gets its
    /// real final score. Returns the number of newly imported games.
    ///
    /// Payloads that can't be confirmed are retried up to N attempts or M days;
    /// after the window they're dropped and surfaced to the user.
    @discardableResult
    func importSharedTickets() async -> Int {
        let pending = SharedTicketStore.load()
        guard !pending.isEmpty else { return 0 }

        var newGames: [AttendedGame] = []
        var existingKeys = Set(games.map(canonicalKey))
        var idsToRemove = Set<String>()
        let now = Date.now

        for payload in pending {
            let message = EmailMessage(
                id: payload.id,
                subject: payload.sourceHint,
                from: payload.sourceHint,
                snippet: payload.text,
                internalDate: payload.receivedAt
            )

            guard let candidate = TicketEmailParser.detect(in: [message]).first else {
                // No MLB matchup at all — drop it so we don't retry forever.
                idsToRemove.insert(payload.id)
                continue
            }

            guard let game = await buildGame(from: candidate) else {
                // Detected a team but couldn't confirm against the schedule.
                var tracking = importAttempts[payload.id] ?? (count: 0, firstSeen: now)
                tracking.count += 1
                importAttempts[payload.id] = tracking
                let age = Calendar.current.dateComponents([.day], from: tracking.firstSeen, to: now).day ?? 0

                if tracking.count >= Self.maxImportAttempts || age >= Self.maxImportAgeDays {
                    // Drop it and surface to user.
                    idsToRemove.insert(payload.id)
                    droppedCandidates.append(DroppedCandidate(
                        id: payload.id,
                        sourceHint: payload.sourceHint,
                        teamMlbId: candidate.teamMlbId,
                        opponentMlbId: candidate.opponentMlbId,
                        snippet: String(payload.text.prefix(200)),
                        reason: "Couldn't confirm after \(tracking.count) attempts over \(age) days"
                    ))
                }
                // Otherwise leave in the queue for next refresh.
                continue
            }

            idsToRemove.insert(payload.id)
            let key = canonicalKey(game)
            guard !existingKeys.contains(key) else { continue }
            existingKeys.insert(key)
            newGames.append(game)
        }

        SharedTicketStore.remove(ids: idsToRemove)

        guard !newGames.isEmpty else { return 0 }

        let inbox = ensureInbox(.shared, label: "Shared tickets")
        var existing = gamesByInbox[inbox.id] ?? []
        existing.append(contentsOf: newGames)
        gamesByInbox[inbox.id] = existing.sorted { $0.date > $1.date }
        if let idx = connectedInboxes.firstIndex(where: { $0.id == inbox.id }) {
            connectedInboxes[idx].ticketsFound = existing.count
        }
        if !hasCompletedOnboarding { hasCompletedOnboarding = true }
        save()
        return newGames.count
    }

    /// Re-check every upcoming game against the MLB schedule; promote any that
    /// have since finished to a completed game with the real final score.
    private func refreshUpcomingScores() async {
        var didChange = false
        for (inboxId, list) in gamesByInbox {
            var updated = list
            for (index, game) in list.enumerated() where game.isUpcoming {
                let teamMlbId = game.homeTeam.mlbId
                let opponentMlbId = game.awayTeam.mlbId
                guard teamMlbId > 0 else { continue }
                guard let results = try? await MLBStatsService.shared.games(on: game.date, teamMlbId: teamMlbId) else {
                    continue
                }
                let match = results.first {
                    ($0.homeMlbId == teamMlbId && $0.awayMlbId == opponentMlbId) ||
                    ($0.awayMlbId == teamMlbId && $0.homeMlbId == opponentMlbId)
                } ?? results.first
                if let match, match.isFinal {
                    let promoted = game.completed(homeScore: match.homeScore, awayScore: match.awayScore)
                    if let details = await MLBStatsService.shared.details(forGamePk: match.gamePk) {
                        updated[index] = promoted.enriched(with: details)
                    } else {
                        updated[index] = promoted
                    }
                    didChange = true
                }
            }
            if updated != list { gamesByInbox[inboxId] = updated }
        }
        if didChange { save() }
    }

    /// Backfill verified facts, highlights and milestones for finished games that
    /// were imported before enrichment existed (or whose detail fetch failed).
    /// Runs on pull-to-refresh so older diary entries gain real box-score data.
    private func enrichExistingGames() async {
        var didChange = false
        for (inboxId, list) in gamesByInbox {
            var updated = list
            for (index, game) in list.enumerated() where !game.isUpcoming && !game.isEnriched {
                let teamMlbId = game.homeTeam.mlbId
                let opponentMlbId = game.awayTeam.mlbId
                guard teamMlbId > 0 else { continue }
                guard let results = try? await MLBStatsService.shared.games(on: game.date, teamMlbId: teamMlbId) else {
                    continue
                }
                let match = results.first {
                    ($0.homeMlbId == teamMlbId && $0.awayMlbId == opponentMlbId) ||
                    ($0.awayMlbId == teamMlbId && $0.homeMlbId == opponentMlbId)
                }
                guard let match, let details = await MLBStatsService.shared.details(forGamePk: match.gamePk) else {
                    continue
                }
                updated[index] = game.enriched(with: details)
                didChange = true
            }
            if updated != list { gamesByInbox[inboxId] = updated }
        }
        if didChange { save() }
    }

    /// Re-verify unverified manual games. On pull-to-refresh, any unverified
    /// manual entry gets checked against the real schedule. If found, it's
    /// updated with the actual box score data and flipped to verified.
    private func reVerifyUnverifiedGames() async {
        var didChange = false
        for (inboxId, list) in gamesByInbox {
            var updated = list
            for (index, game) in list.enumerated() where !game.verified && !game.isUpcoming {
                let homeMlbId = game.homeTeam.mlbId
                let awayMlbId = game.awayTeam.mlbId
                guard homeMlbId > 0 else { continue }
                guard let results = try? await MLBStatsService.shared.games(on: game.date, teamMlbId: homeMlbId) else {
                    continue
                }
                let match = results.first {
                    ($0.homeMlbId == homeMlbId && $0.awayMlbId == awayMlbId) ||
                    ($0.awayMlbId == homeMlbId && $0.homeMlbId == awayMlbId)
                }
                if let match, match.isFinal {
                    // Found the real game — update with verified data.
                    if let details = await MLBStatsService.shared.details(forGamePk: match.gamePk) {
                        updated[index] = game.enriched(with: details)
                    } else {
                        updated[index] = AttendedGame(
                            id: game.id, date: game.date, ballparkId: game.ballparkId,
                            homeTeamId: game.homeTeamId, awayTeamId: game.awayTeamId,
                            homeScore: match.homeScore, awayScore: match.awayScore,
                            userRootedForHome: game.userRootedForHome,
                            section: game.section, row: game.row, seat: game.seat,
                            confirmation: game.confirmation,
                            weather: game.weather, firstPitchTempF: game.firstPitchTempF,
                            attendance: game.attendance, durationMinutes: game.durationMinutes,
                            highlights: game.highlights, milestones: game.milestones,
                            emailSubject: game.emailSubject, source: game.source,
                            status: .completed, isVerified: true
                        )
                    }
                    didChange = true
                }
            }
            if updated != list { gamesByInbox[inboxId] = updated }
        }
        if didChange { save() }
    }

    /// Resolve a detected ticket to a real MLB game. Strictly verified: when both
    /// teams are known we only accept a game where those exact two teams play
    /// each other, and we never substitute a different game on a fallback date.
    /// If the ticket's year is ambiguous we search the same month/day across
    /// recent seasons — a specific matchup is rare enough that only the real year
    /// confirms. Returns nil rather than inventing a wrong game.
    private func buildGame(from candidate: DetectedGame) async -> AttendedGame? {
        for date in confirmationDates(for: candidate) {
            guard
                let results = try? await MLBStatsService.shared.games(on: date, teamMlbId: candidate.teamMlbId),
                !results.isEmpty
            else { continue }

            let match: MLBGameResult?
            if let opponent = candidate.opponentMlbId {
                // Require the exact matchup — home/away in either order.
                match = results.first { result in
                    (result.homeMlbId == candidate.teamMlbId && result.awayMlbId == opponent) ||
                    (result.awayMlbId == candidate.teamMlbId && result.homeMlbId == opponent)
                }
            } else {
                // Only one team known: a team plays at most one opponent per day,
                // so a single game on this exact date is unambiguous.
                match = results.first { result in
                    result.homeMlbId == candidate.teamMlbId || result.awayMlbId == candidate.teamMlbId
                }
            }

            if let match {
                guard let base = AttendedGame.from(
                    result: match,
                    source: candidate.source,
                    emailSubject: candidate.subject,
                    favoriteTeamId: favoriteTeamId,
                    section: candidate.section,
                    row: candidate.row,
                    seat: candidate.seat,
                    confirmation: candidate.confirmation
                ) else { return nil }
                // Pull verified facts, scoring plays and milestones for finished games.
                if !base.isUpcoming, let details = await MLBStatsService.shared.details(forGamePk: match.gamePk) {
                    return base.enriched(with: details)
                }
                return base
            }
        }
        return nil
    }

    /// Concrete dates to check against the schedule, derived from the ticket's
    /// date hints. When the matchup is known (both teams) we expand an ambiguous
    /// year across recent seasons so the real game resolves itself; with only one
    /// team we stay close to the present to avoid picking the wrong season.
    private func confirmationDates(for candidate: DetectedGame) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let thisYear = cal.component(.year, from: .now)
        var dates: [Date] = []
        var seen = Set<String>()

        func add(year: Int, month: Int, day: Int) {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
            guard let date = cal.date(from: comps) else { return }
            let key = "\(year)-\(month)-\(day)"
            if seen.insert(key).inserted { dates.append(date) }
        }

        for hint in candidate.dateHints {
            if let year = hint.year {
                add(year: year, month: hint.month, day: hint.day)
            }
            if candidate.opponentMlbId != nil {
                // Matchup is rare — safe to scan many recent seasons (newest first).
                for year in stride(from: thisYear, through: thisYear - 12, by: -1) {
                    add(year: year, month: hint.month, day: hint.day)
                }
            } else if hint.year == nil {
                // Single team, unknown year: best-effort guess at recent seasons.
                add(year: thisYear, month: hint.month, day: hint.day)
                add(year: thisYear - 1, month: hint.month, day: hint.day)
            }
        }
        return dates
    }

    // MARK: - Dedup on launch

    /// One-time cleanup that collapses duplicate games by canonical key,
    /// keeping the most-enriched copy (the one with highlights/milestones/attendance).
    private func collapseDuplicates() {
        var seen: [String: (inboxId: UUID, game: AttendedGame)] = [:]
        var toRemove: [(UUID, UUID)] = [] // (inboxId, gameId)

        for (inboxId, list) in gamesByInbox {
            for game in list {
                let key = canonicalKey(game)
                if let existing = seen[key] {
                    // Keep the most-enriched copy
                    let keepExisting = existing.game.isEnriched || (!existing.game.isEnriched && !game.isEnriched)
                    if !keepExisting {
                        // The new game is richer — remove the old one
                        toRemove.append((existing.inboxId, existing.game.id))
                        seen[key] = (inboxId, game)
                    } else {
                        toRemove.append((inboxId, game.id))
                    }
                } else {
                    seen[key] = (inboxId, game)
                }
            }
        }

        guard !toRemove.isEmpty else { return }

        for (inboxId, gameId) in toRemove {
            if var list = gamesByInbox[inboxId] {
                list.removeAll { $0.id == gameId }
                if list.isEmpty {
                    gamesByInbox.removeValue(forKey: inboxId)
                } else {
                    gamesByInbox[inboxId] = list
                }
            }
        }

        // Refresh inbox counts
        for (index, inbox) in connectedInboxes.enumerated() {
            connectedInboxes[index].ticketsFound = gamesByInbox[inbox.id]?.count ?? 0
        }
        connectedInboxes.removeAll { gamesByInbox[$0.id] == nil }

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
        var droppedCandidates: [DroppedCandidate]
    }

    private func save() {
        let snapshot = Snapshot(
            favoriteTeamId: favoriteTeamId,
            hasPickedFavorite: hasPickedFavorite,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasAcceptedTerms: hasAcceptedTerms,
            inboxes: connectedInboxes,
            gamesByInbox: Dictionary(uniqueKeysWithValues: gamesByInbox.map { ($0.key.uuidString, $0.value) }),
            droppedCandidates: droppedCandidates
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
        droppedCandidates = snapshot.droppedCandidates
    }
}

/// A candidate that couldn't be confirmed and was dropped after the retry window.
/// Surfaced to the user so they can manually add it instead of it silently vanishing.
struct DroppedCandidate: Identifiable, Codable, Hashable {
    let id: String
    let sourceHint: String
    let teamMlbId: Int
    let opponentMlbId: Int?
    let snippet: String
    let reason: String
}
