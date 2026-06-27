import Foundation
import Observation
import CoreLocation
import SwiftUI

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

    /// True when the share extension deep-link should open the manual-entry sheet.
    /// Observed by InboxesView to auto-present ManualGameEntryView.
    var requestedManualEntry: Bool = false

    /// The ID of the most recently imported game from a share extension ticket.
    /// Set during `importSharedTickets()` and consumed by `DiaryView` to
    /// auto-navigate to the game detail so the user can verify the imported data.
    var lastImportedGameId: UUID? = nil

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

    // MARK: - Achievements (computed badges)

    /// Achievements: id, unlocked, and the data needed to display the badge.
    /// Order matters — it determines the grid display order.
    var achievementList: [Achievement] {
        collectionAchievements + divisionAchievements + gameExperienceAchievements
            + fanDedicationAchievements + roadRivalryAchievements
    }

    private var collectionAchievements: [Achievement] {
        [
            Achievement(id: "first", symbol: "ticket.fill", title: "First Game", detail: "Welcome to the diary", unlocked: totalGames >= 1, tint: Theme.clay, tier: .free),
            Achievement(id: "five_parks", symbol: "building.columns.fill", title: "Five Stadiums", detail: "Visit 5 unique ballparks", unlocked: ballparkCount >= 5, tint: Theme.lights, tier: .free),
            Achievement(id: "ten_parks", symbol: "building.2.fill", title: "Ten Stadiums", detail: "Visit 10 unique ballparks", unlocked: ballparkCount >= 10, tint: Theme.lights, tier: .free),
            Achievement(id: "twenty_parks", symbol: "map.fill", title: "Road Tripper", detail: "Visit 20 unique ballparks", unlocked: ballparkCount >= 20, tint: Theme.lights, tier: .free),
            Achievement(id: "thirty_parks", symbol: "crown.fill", title: "Pilgrim", detail: "All 30 ballparks visited", unlocked: ballparkCount == 30, tint: Theme.lights, tier: .free),
            Achievement(id: "coast", symbol: "globe.americas.fill", title: "Coast to Coast", detail: "AL East + NL West", unlocked: coastToCoast, tint: Theme.grass, tier: .free),
        ]
    }

    private var divisionAchievements: [Achievement] {
        [
            Achievement(id: "div_ale", symbol: "star.fill", title: "AL East", detail: "All 5 AL East parks", unlocked: divisionComplete(Self.alEast), tint: Team.yankees.primary, tier: .pro),
            Achievement(id: "div_alc", symbol: "star.fill", title: "AL Central", detail: "All 5 AL Central parks", unlocked: divisionComplete(Self.alCentral), tint: Team.guardians.primary, tier: .pro),
            Achievement(id: "div_alw", symbol: "star.fill", title: "AL West", detail: "All 5 AL West parks", unlocked: divisionComplete(Self.alWest), tint: Team.astros.primary, tier: .pro),
            Achievement(id: "div_nle", symbol: "star.fill", title: "NL East", detail: "All 5 NL East parks", unlocked: divisionComplete(Self.nlEast), tint: Team.braves.primary, tier: .pro),
            Achievement(id: "div_nlc", symbol: "star.fill", title: "NL Central", detail: "All 5 NL Central parks", unlocked: divisionComplete(Self.nlCentral), tint: Team.cubs.primary, tier: .pro),
            Achievement(id: "div_nlw", symbol: "star.fill", title: "NL West", detail: "All 5 NL West parks", unlocked: divisionComplete(Self.nlWest), tint: Team.dodgers.primary, tier: .pro),
            Achievement(id: "league", symbol: "arrow.left.and.right", title: "Both Leagues", detail: "Parks in AL and NL", unlocked: visitedBothLeagues, tint: Theme.clay, tier: .pro),
        ]
    }

    private var gameExperienceAchievements: [Achievement] {
        [
            Achievement(id: "extras", symbol: "clock.arrow.2.circlepath", title: "Extra Innings", detail: "Free baseball!", unlocked: witnessedExtraInnings, tint: Theme.lights, tier: .free),
            Achievement(id: "walkoff", symbol: "star.circle.fill", title: "Walk-Off", detail: "Game decided in final AB", unlocked: witnessedWalkoff, tint: Theme.foul, tier: .free),
            Achievement(id: "blowout", symbol: "flame.fill", title: "Blowout", detail: "10+ run difference", unlocked: witnessedBlowout, tint: Theme.foul, tier: .free),
            Achievement(id: "duel", symbol: "hand.point.up.fill", title: "Pitcher's Duel", detail: "2 or fewer total runs", unlocked: witnessedPitchersDuel, tint: Theme.clayDeep, tier: .free),
            Achievement(id: "shutout", symbol: "lock.shield.fill", title: "Shutout", detail: "One team held scoreless", unlocked: witnessedShutout, tint: Theme.grass, tier: .free),
            Achievement(id: "slugfest", symbol: "baseball.fill", title: "Slugfest", detail: "5+ home runs", unlocked: witnessedSlugfest, tint: Theme.lights, tier: .free),
            Achievement(id: "sunday", symbol: "sun.max.fill", title: "Sunday Afternoon", detail: "Day game on a Sunday", unlocked: witnessedSundayDayGame, tint: Theme.lights, tier: .free),
            Achievement(id: "rain", symbol: "cloud.rain.fill", title: "Rain or Shine", detail: "Stuck through a rain delay", unlocked: witnessedRainDelay, tint: Theme.clay, tier: .free),
        ]
    }

    private var fanDedicationAchievements: [Achievement] {
        [
            Achievement(id: "die_hard", symbol: "heart.fill", title: "Die Hard", detail: "10+ games in a season", unlocked: dieHardFan, tint: Theme.foul, tier: .free),
            Achievement(id: "iron_fan", symbol: "figure.baseball", title: "Iron Fan", detail: "25+ lifetime games", unlocked: totalGames >= 25, tint: Theme.clay, tier: .free),
            Achievement(id: "silver_slugger", symbol: "medal.fill", title: "Silver Slugger", detail: "50+ lifetime games", unlocked: totalGames >= 50, tint: Theme.lights, tier: .free),
            Achievement(id: "century", symbol: "100.circle", title: "Century Club", detail: "100+ lifetime games", unlocked: totalGames >= 100, tint: Theme.lights, tier: .free),
            Achievement(id: "back_to_back", symbol: "arrow.triangle.pull", title: "Back-to-Back", detail: "Consecutive days", unlocked: didBackToBack, tint: Theme.clayDeep, tier: .free),
            Achievement(id: "streak", symbol: "flame.fill", title: "Win Streak x3", detail: "3 wins in a row", unlocked: longestStreak >= 3, tint: Theme.clayDeep, tier: .free),
            Achievement(id: "streak5", symbol: "bolt.fill", title: "Win Streak x5", detail: "5 wins in a row", unlocked: longestStreak >= 5, tint: Theme.lights, tier: .free),
        ]
    }

    private var roadRivalryAchievements: [Achievement] {
        [
            Achievement(id: "road_warrior", symbol: "car.fill", title: "Road Warrior", detail: "3+ away parks", unlocked: roadWarrior, tint: Theme.clay, tier: .pro),
            Achievement(id: "international", symbol: "airplane", title: "International", detail: "Crossed the border", unlocked: visitedInternational, tint: Team.blueJays.primary, tier: .free),
            Achievement(id: "dome_dweller", symbol: "building.fill", title: "Dome Dweller", detail: "Every indoor park", unlocked: domeDweller, tint: Theme.grass, tier: .pro),
            Achievement(id: "rivalry_subway", symbol: "train.side.front.car", title: "Subway Series", detail: "NYY vs NYM", unlocked: witnessedRivalry("nyy", "nym"), tint: Team.yankees.primary, tier: .pro),
            Achievement(id: "rivalry_freeway", symbol: "car.rear.road.lane", title: "Freeway Series", detail: "LAD vs LAA", unlocked: witnessedRivalry("lad", "laa"), tint: Team.dodgers.primary, tier: .pro),
            Achievement(id: "rivalry_crosstown", symbol: "building.2.fill", title: "Crosstown Classic", detail: "CHC vs CWS", unlocked: witnessedRivalry("chc", "cws"), tint: Team.cubs.primary, tier: .pro),
            Achievement(id: "rivalry_ohio", symbol: "map.fill", title: "Battle of Ohio", detail: "CIN vs CLE", unlocked: witnessedRivalry("cin", "cle"), tint: Team.reds.primary, tier: .pro),
            Achievement(id: "rivalry_lonestar", symbol: "star.fill", title: "Lone Star", detail: "TEX vs HOU", unlocked: witnessedRivalry("tex", "hou"), tint: Team.rangers.primary, tier: .pro),
        ]
    }

    // ── Achievement Detectors ──

    struct MLBDivision { let name: String; let teamIds: Set<String> }
    static let alEast    = MLBDivision(name: "AL East",    teamIds: ["nyy", "bos", "tor", "bal", "tb"])
    static let alCentral = MLBDivision(name: "AL Central", teamIds: ["cle", "det", "kc",  "min", "cws"])
    static let alWest    = MLBDivision(name: "AL West",    teamIds: ["hou", "laa", "ath", "sea", "tex"])
    static let nlEast    = MLBDivision(name: "NL East",    teamIds: ["atl", "mia", "nym", "phi", "wsh"])
    static let nlCentral = MLBDivision(name: "NL Central", teamIds: ["chc", "cin", "mil", "pit", "stl"])
    static let nlWest    = MLBDivision(name: "NL West",    teamIds: ["ari", "col", "lad", "sd",  "sf"])

    private func divisionComplete(_ div: MLBDivision) -> Bool {
        let homeParks = div.teamIds.compactMap { Ballpark.by(teamId: $0)?.id }
        return homeParks.allSatisfy(visitedBallparkIds.contains)
    }

    private var visitedBothLeagues: Bool {
        let al = visitedBallparkIds.compactMap { Ballpark.by(id: $0) }.contains { park in
            Self.alEast.teamIds.contains(park.team.id) || Self.alCentral.teamIds.contains(park.team.id) || Self.alWest.teamIds.contains(park.team.id)
        }
        let nl = visitedBallparkIds.compactMap { Ballpark.by(id: $0) }.contains { park in
            Self.nlEast.teamIds.contains(park.team.id) || Self.nlCentral.teamIds.contains(park.team.id) || Self.nlWest.teamIds.contains(park.team.id)
        }
        return al && nl
    }

    var coastToCoast: Bool {
        let east = visitedBallparkIds.intersection(["yankee-stadium", "fenway-park", "citi-field", "citizens-bank-park"])
        let west = visitedBallparkIds.intersection(["dodger-stadium", "oracle-park", "petco-park", "angel-stadium"])
        return !east.isEmpty && !west.isEmpty
    }

    var witnessedWalkoff: Bool {
        games.flatMap(\.highlights).contains { $0.kind == .walkoff }
    }

    var witnessedExtraInnings: Bool {
        games.flatMap(\.highlights).contains { h in
            if let inningNum = Int(h.inning.dropFirst()), inningNum >= 10 { return true }
            return false
        }
    }

    var witnessedBlowout: Bool {
        completedGames.contains { abs($0.homeScore - $0.awayScore) >= 10 }
    }

    var witnessedPitchersDuel: Bool {
        completedGames.contains { ($0.homeScore + $0.awayScore) <= 2 }
    }

    var witnessedShutout: Bool {
        completedGames.contains { $0.homeScore == 0 || $0.awayScore == 0 }
    }

    var witnessedSlugfest: Bool {
        completedGames.contains { g in
            g.highlights.filter { $0.kind == .homeRun }.count >= 5
        }
    }

    var witnessedSundayDayGame: Bool {
        completedGames.contains { g in
            let weekday = Calendar.current.component(.weekday, from: g.date)
            return weekday == 1 && g.weather == .clear
        }
    }

    var witnessedRainDelay: Bool {
        completedGames.contains { $0.weather == .rain }
    }

    var dieHardFan: Bool {
        let groups = Dictionary(grouping: completedGames) { Calendar.current.component(.year, from: $0.date) }
        return groups.values.contains { $0.count >= 10 }
    }

    var didBackToBack: Bool {
        let sorted = completedGames.map(\.date).sorted()
        for i in 1..<sorted.count {
            let diff = Calendar.current.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day ?? 99
            if diff == 1 { return true }
        }
        return false
    }

    var visitedInternational: Bool {
        visitedBallparkIds.contains("rogers-centre")
    }

    var domeDweller: Bool {
        let domeParks = Ballpark.all.filter { $0.roof != .open }.map(\.id)
        return !domeParks.isEmpty && domeParks.allSatisfy(visitedBallparkIds.contains)
    }

    var roadWarrior: Bool {
        let fav = favoriteTeam
        let awayParks = completedGames
            .filter { ($0.homeTeamId == fav.id && !$0.userRootedForHome) || ($0.awayTeamId == fav.id && $0.userRootedForHome) }
            .map(\.ballparkId)
        return Set(awayParks).count >= 3
    }

    func witnessedRivalry(_ teamA: String, _ teamB: String) -> Bool {
        completedGames.contains { g in
            let ids = [g.homeTeamId, g.awayTeamId]
            return ids.contains(teamA) && ids.contains(teamB)
        }
    }

    // ── Ballpark Facts (fun discoveries) ──

    /// Fun fact for a park — delegates to the per-park discovery catalog.
    func discoveryFor(_ park: Ballpark) -> String { park.discoveryFact() }

    /// Nearby parks the user hasn't visited yet, sorted by distance from the
    /// user's favorite team's home ballpark (or current city).
    func nearestUnvisitedParks(limit: Int = 3) -> [Ballpark] {
        let homeCoordinate = Ballpark.by(teamId: favoriteTeamId)?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.5, longitude: -96.0)
        let homeLoc = CLLocation(latitude: homeCoordinate.latitude, longitude: homeCoordinate.longitude)
        return ballparksRemaining.sorted { a, b in
            let da = homeLoc.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
            let db = homeLoc.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            return da < db
        }.prefix(limit).map { $0 }
    }

    /// Parks visited in chronological order — used to draw journey lines on the map.
    var visitedParkSequence: [Ballpark] {
        let chrono = completedGames.sorted { $0.date < $1.date }
        var seen: Set<String> = []
        return chrono.compactMap { game -> Ballpark? in
            guard !seen.contains(game.ballparkId) else { return nil }
            seen.insert(game.ballparkId)
            return game.ballpark
        }
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

    /// Update which team the user rooted for on a saved game. Flips the
    /// win/loss outcome derived from `userWon` so stats stay correct.
    func setRootedForHome(_ id: UUID, rootedForHome: Bool) {
        for (inboxId, list) in gamesByInbox {
            guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
            let g = list[index]
            guard g.userRootedForHome != rootedForHome else { return }
            var updated = list
            updated[index] = g.rooting(forHome: rootedForHome)
            gamesByInbox[inboxId] = updated
            save()
            return
        }
    }

    /// Update seat info (section, row, seat) for a verified ticket.
    /// Does nothing if the game ID is not found in the diary.
    func setSeatInfo(_ id: UUID, section: String, row: String, seat: String) {
        for (inboxId, list) in gamesByInbox {
            guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
            var updated = list
            updated[index] = updated[index].withSeat(section: section, row: row, seat: seat)
            gamesByInbox[inboxId] = updated
            save()
            return
        }
    }

    /// Look up a game by its ID across all inboxes. Returns nil if not found.
    /// Use this instead of passing AttendedGame value types through navigation
    /// when the game may be mutated by the store (e.g. rooted-for changes).
    func game(id: UUID) -> AttendedGame? {
        for list in gamesByInbox.values {
            if let game = list.first(where: { $0.id == id }) { return game }
        }
        return nil
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

    /// Guards against overlapping shared-ticket imports so the share-extension
    /// URL handler and the periodic refresh don't race and double-add games.
    private var isImporting: Bool = false

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
        guard !isImporting else { return 0 }
        isImporting = true
        defer { isImporting = false }

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

        // Record the most recently imported game so the diary can auto-navigate.
        lastImportedGameId = newGames.last?.id

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

    /// Reset the entire diary back to its fresh state. All games, inboxes, and
    /// preferences are cleared. The user will re-enter onboarding on next launch.
    func resetAll() {
        gamesByInbox.removeAll()
        connectedInboxes.removeAll()
        droppedCandidates.removeAll()
        importAttempts.removeAll()
        lastRefreshAt = nil
        favoriteTeamId = Team.yankees.id
        hasPickedFavorite = false
        hasCompletedOnboarding = false
        hasAcceptedTerms = false
        defaults.removeObject(forKey: storageKey)
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
        // Use uniquingKeysWith to safely handle any accidental duplicates
        // instead of crashing on Dictionary(uniqueKeysWithValues:).
        let pairs: [(UUID, [AttendedGame])] = snapshot.gamesByInbox.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        }
        gamesByInbox = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
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

// MARK: - Achievement model

/// A badge the user can earn by attending games, visiting parks, or
/// witnessing rare baseball events.
struct Achievement: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let unlocked: Bool
    let tint: Color
    let tier: Tier

    enum Tier { case free, pro }
}
