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

    /// Surfaces MLB API failures to the UI so the user knows a refresh didn't
    /// reach the server. Cleared on the next successful refresh.
    var lastRefreshError: String? = nil

    var favoriteTeamId: String = Team.yankees.id

    /// Attended games keyed by the source they came from (shared tickets or
    /// manual entries). The merged diary (`games`) is the union of every value.
    var gamesByInbox: [UUID: [AttendedGame]] = [:]

    /// Successfully connected sources (shown in the Inboxes tab).
    var connectedInboxes: [ConnectedInbox] = []

    /// Games that couldn't be confirmed and were dropped — surfaced to user.
    var droppedCandidates: [DroppedCandidate] = []

    /// Potential duplicate entries detected during import. The user reviews
    /// each one and decides to keep or discard the flagged game.
    var flaggedDuplicates: [FlaggedDuplicate] = []

    /// When true, near-duplicate tickets are silently auto-deleted without
    /// prompting. The user can toggle this from the flagged duplicates section.
    var autoDeleteDuplicates: Bool = false

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

    /// Tracks the detached 180-second follow-up refresh Task so repeated pulls
    /// don't stack up multiple delayed refreshes.
    private var followUpRefreshTask: Task<Void, Never>?

    // MARK: - Stats memoization
    /// Cached computed stats — invalidated on save() once the diary exceeds
    /// ~100 games so repeated property access doesn't recompute expensive
    /// aggregates on every view render.
    private var cachedAchievementList: [Achievement]? = nil
    private var cachedMilesTraveled: Double? = nil
    private var cachedVisitedParkSequence: [Ballpark]? = nil
    private var statsCacheGameCount: Int = 0

    private let defaults = UserDefaults.standard
    private let storageKey = "ballparkdiary.state.v2"
    private let autoDeleteKey = "ballparkdiary.autoDeleteDuplicates"

    /// File URL for the diary JSON blob in Application Support.
    private let diaryFileURL: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = appSupport.appendingPathComponent("BallparkDiary", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("diary.json")
    }()

    /// Max failed import attempts before dropping a payload.
    private static let maxImportAttempts = 5
    /// Max days a payload can sit unconfirmed before dropping.
    private static let maxImportAgeDays = 7

    init() {
        load()
        collapseDuplicates()
        autoDeleteDuplicates = defaults.bool(forKey: autoDeleteKey)
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
    /// Games where the user explicitly rooted for a team (not neutral).
    var rootedGames: [AttendedGame] { completedGames.filter { $0.userRootedForHome != nil } }

    var winCount: Int { rootedGames.filter(\.userWon).count }
    var lossCount: Int { rootedGames.count - winCount }
    var winPct: Double {
        guard !rootedGames.isEmpty else { return 0 }
        return Double(winCount) / Double(rootedGames.count)
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
            let opp = g.userRootedForHome == true ? g.awayTeamId : g.homeTeamId
            seen[opp, default: 0] += 1
        }
        guard let top = seen.max(by: { $0.value < $1.value }), let team = Team.by(id: top.key) else { return nil }
        return (team, top.value)
    }

    var longestStreak: Int {
        let chrono = rootedGames.sorted { $0.date < $1.date }
        var best = 0, run = 0
        for g in chrono { if g.userWon { run += 1; best = max(best, run) } else { run = 0 } }
        return best
    }

    // MARK: Deeper stats

    /// Total minutes of baseball watched, summed from verified game durations.
    var totalMinutesWatched: Int { completedGames.reduce(0) { $0 + $1.durationMinutes } }

    /// Human-readable total time at the ballpark.
    var totalTimeLabel: String {
        let hours = totalMinutesWatched / 60
        let mins = totalMinutesWatched % 60
        if hours > 0 { return "\(hours) h \(mins) m" }
        return "\(mins) min"
    }

    /// Total miles traveled between ballparks, computed from chronological visits.
    var milesTraveled: Double {
        if let cached = cachedMilesTraveled, statsCacheGameCount == games.count {
            return cached
        }
        let parks = visitedParkSequence
        guard parks.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<parks.count {
            let prev = CLLocation(latitude: parks[i-1].latitude, longitude: parks[i-1].longitude)
            let curr = CLLocation(latitude: parks[i].latitude, longitude: parks[i].longitude)
            total += prev.distance(from: curr) * 0.000621371 // meters to miles
        }
        if games.count > 100 {
            cachedMilesTraveled = total
            statsCacheGameCount = games.count
        }
        return total
    }

    /// Number of distinct calendar years with attended games.
    var seasonsActive: Int {
        let years = Set(completedGames.map { Calendar.current.component(.year, from: $0.date) })
        return years.count
    }

    /// Years since the first attended game.
    var baseballAge: Int {
        guard let first = completedGames.map(\.date).min() else { return 0 }
        return Calendar.current.dateComponents([.year], from: first, to: .now).year ?? 0
    }

    /// Average combined runs per completed game.
    var averageRunsPerGame: Double {
        guard !completedGames.isEmpty else { return 0 }
        return Double(totalRuns) / Double(completedGames.count)
    }

    /// Count of day games attended.
    var dayGameCount: Int {
        completedGames.filter { $0.weather == .clear || $0.weather == .partlyCloudy || $0.weather == .cloudy }.count
    }

    /// Count of night games attended.
    var nightGameCount: Int {
        completedGames.filter { $0.weather == .night }.count
    }

    /// Month with the best win percentage (minimum 2 games). Returns (monthName, winPct, games).
    var bestMonth: (name: String, winPct: Double, games: Int)? {
        let grouped = Dictionary(grouping: rootedGames) {
            Calendar.current.component(.month, from: $0.date)
        }
        var best: (name: String, winPct: Double, games: Int)?
        for (month, games) in grouped where games.count >= 2 {
            let wins = games.filter(\.userWon).count
            let pct = Double(wins) / Double(games.count)
            let name = Calendar.current.monthSymbols[month - 1]
            if best == nil || pct > best?.winPct ?? 0 { best = (name, pct, games.count) }
        }
        return best
    }

    /// Count of 1-run games attended.
    var oneRunGames: Int {
        completedGames.filter { abs($0.homeScore - $0.awayScore) == 1 }.count
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
        if let cached = cachedAchievementList, statsCacheGameCount == games.count {
            return cached
        }
        let result = collectionAchievements + divisionAchievements + gameExperienceAchievements
            + fanDedicationAchievements + roadRivalryAchievements + hiddenAchievements
        if games.count > 100 {
            cachedAchievementList = result
            statsCacheGameCount = games.count
        }
        return result
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

    // MARK: - Hidden achievements (surprise badges)

    /// Hidden achievements only appear after they're unlocked — stadium-specific,
    /// rare-event, and deep-cut badges the user discovers naturally.
    private var hiddenAchievements: [Achievement] {
        let all: [Achievement] = [
            // ── Stadium-specific badges ──
            Achievement(id: "hid_fenway", symbol: "building.columns.fill", title: "Green Monster", detail: "You've stood before the Wall", unlocked: visitedPark("fenway-park"), tint: Team.redSox.primary, tier: .free, hidden: true),
            Achievement(id: "hid_wrigley", symbol: "leaf.fill", title: "Ivy League", detail: "You've been to the Friendly Confines", unlocked: visitedPark("wrigley-field"), tint: Team.cubs.primary, tier: .free, hidden: true),
            Achievement(id: "hid_bronx", symbol: "crown.fill", title: "Bronx Bomber", detail: "You walked Monument Park", unlocked: visitedPark("yankee-stadium"), tint: Team.yankees.primary, tier: .free, hidden: true),
            Achievement(id: "hid_ravine", symbol: "mountain.2.fill", title: "Chavez Ravine", detail: "Sunset over Dodger Stadium", unlocked: visitedPark("dodger-stadium"), tint: Team.dodgers.primary, tier: .free, hidden: true),
            Achievement(id: "hid_splash", symbol: "water.waves", title: "Splash Hit", detail: "McCovey Cove is real", unlocked: visitedPark("oracle-park"), tint: Team.giants.primary, tier: .free, hidden: true),
            Achievement(id: "hid_gateway", symbol: "binoculars.fill", title: "Gateway to the West", detail: "The Arch frames center field", unlocked: visitedPark("busch-stadium"), tint: Team.cardinals.primary, tier: .free, hidden: true),
            Achievement(id: "hid_milehigh", symbol: "mountain.2.fill", title: "Mile High Club", detail: "You sat in the purple seats", unlocked: visitedPark("coors-field"), tint: Team.rockies.primary, tier: .free, hidden: true),
            Achievement(id: "hid_bigA", symbol: "a.circle.fill", title: "The Big A", detail: "Angel Stadium — the halo shines", unlocked: visitedPark("angel-stadium"), tint: Team.angels.primary, tier: .free, hidden: true),
            Achievement(id: "hid_classic_trio", symbol: "3.circle.fill", title: "Classic Trio", detail: "Fenway, Wrigley & Dodger — the last of their kind", unlocked: classicTrio, tint: Theme.parchmentInk, tier: .free, hidden: true),
            Achievement(id: "hid_fountain", symbol: "drop.fill", title: "Fountain Finder", detail: "You found the Kauffman waterfalls", unlocked: visitedPark("kauffman-stadium"), tint: Team.royals.primary, tier: .free, hidden: true),
            Achievement(id: "hid_warehouse", symbol: "building.2.fill", title: "B&O Warehouse", detail: "Eutaw Street magic at Camden Yards", unlocked: visitedPark("camden-yards"), tint: Team.orioles.primary, tier: .free, hidden: true),
            Achievement(id: "hid_bridge", symbol: "figure.walk", title: "Clemente Bridge", detail: "You walked the bridge to PNC Park", unlocked: visitedPark("pnc-park"), tint: Team.pirates.primary, tier: .free, hidden: true),

            // ── Rare game events ──
            Achievement(id: "hid_marathon", symbol: "clock.arrow.2.circlepath", title: "Marathon", detail: "A 15+ inning epic", unlocked: witnessedMarathon, tint: Theme.clayDeep, tier: .free, hidden: true),
            Achievement(id: "hid_one_run", symbol: "scissors", title: "Nail-Biter", detail: "5+ one-run games", unlocked: oneRunGames >= 5, tint: Theme.foul, tier: .free, hidden: true),
            Achievement(id: "hid_blowout15", symbol: "flame.circle.fill", title: "Rout Master", detail: "Witnessed a 15+ run blowout", unlocked: witnessedBlowout15, tint: Theme.lights, tier: .free, hidden: true),
            Achievement(id: "hid_no_hitter", symbol: "hand.raised.fill", title: "No-No", detail: "You were there for a no-hitter", unlocked: witnessedNoHitter, tint: Theme.chalk, tier: .free, hidden: true),
            Achievement(id: "hid_perfect", symbol: "sparkles", title: "Perfection", detail: "27 up, 27 down — a perfect game", unlocked: witnessedPerfectGame, tint: Theme.lights, tier: .free, hidden: true),
            Achievement(id: "hid_cycle", symbol: "arrow.triangle.2.circlepath", title: "Hit for the Cycle", detail: "Single, double, triple, homer — one player", unlocked: witnessedCycle, tint: Theme.grass, tier: .free, hidden: true),

            // ── Deep-cut stats ──
            Achievement(id: "hid_decade", symbol: "calendar.badge.clock", title: "Decade Fan", detail: "Games across 10+ seasons", unlocked: seasonsActive >= 10, tint: Theme.clay, tier: .free, hidden: true),
            Achievement(id: "hid_500hr", symbol: "star.circle.fill", title: "Historic Clout", detail: "Saw a 500th career home run", unlocked: witnessedFamousHRMark(500), tint: Theme.lights, tier: .free, hidden: true),
            Achievement(id: "hid_600hr", symbol: "star.square.fill", title: "Inner Circle", detail: "Saw a 600th career home run", unlocked: witnessedFamousHRMark(600), tint: Theme.lights, tier: .free, hidden: true),
            Achievement(id: "hid_3000hit", symbol: "figure.baseball", title: "Three Thousand", detail: "Witnessed a 3,000th career hit", unlocked: witnessed3000Hit, tint: Theme.grass, tier: .free, hidden: true),
            Achievement(id: "hid_300k", symbol: "flame.fill", title: "The 300 Club", detail: "Saw a 300-strikeout game", unlocked: witnessed300KStrikeoutGame, tint: Theme.foul, tier: .free, hidden: true),
            Achievement(id: "hid_10000", symbol: "clock.badge.fill", title: "Five Digits", detail: "10,000+ minutes at the ballpark", unlocked: totalMinutesWatched >= 10000, tint: Theme.clayDeep, tier: .free, hidden: true),
            Achievement(id: "hid_iron_butt", symbol: "chair.lounge.fill", title: "Iron Butt", detail: "20,000+ minutes — that's two weeks", unlocked: totalMinutesWatched >= 20000, tint: Theme.lights, tier: .free, hidden: true),
            Achievement(id: "hid_10k_miles", symbol: "globe.americas.fill", title: "Cross-Country", detail: "10,000+ miles traveled between parks", unlocked: milesTraveled >= 10000, tint: Theme.grass, tier: .free, hidden: true),
            Achievement(id: "hid_grand_slam", symbol: "baseball.diamond.fill", title: "Grand Salami", detail: "Saw a grand slam live", unlocked: witnessedGrandSlam, tint: Theme.lights, tier: .free, hidden: true),
            Achievement(id: "hid_inside_park", symbol: "figure.run", title: "Inside Job", detail: "Saw an inside-the-park home run", unlocked: witnessedInsideTheParkHR, tint: Theme.clay, tier: .free, hidden: true),
        ]
        // Only surface unlocked hidden badges — locked ones stay invisible.
        return all.filter { !$0.hidden || $0.unlocked }
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
        completedGames.flatMap(\.highlights).contains { $0.kind == .walkoff }
    }

    var witnessedExtraInnings: Bool {
        completedGames.flatMap(\.highlights).contains { h in
            if let inningNum = Int(h.inning.dropFirst()), inningNum >= 10 { return true }
            return false
        }
    }

    /// Attended a game that went 15+ innings.
    var witnessedMarathon: Bool {
        completedGames.flatMap(\.highlights).contains { h in
            if let inningNum = Int(h.inning.dropFirst()), inningNum >= 15 { return true }
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
            return weekday == 1 && (g.weather == .clear || g.weather == .partlyCloudy || g.weather == .cloudy)
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
        guard sorted.count >= 2 else { return false }
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
            .filter { ($0.homeTeamId == fav.id && $0.userRootedForHome == false) || ($0.awayTeamId == fav.id && $0.userRootedForHome == true) }
            .map(\.ballparkId)
        return Set(awayParks).count >= 3
    }

    func witnessedRivalry(_ teamA: String, _ teamB: String) -> Bool {
        completedGames.contains { g in
            let ids = [g.homeTeamId, g.awayTeamId]
            return ids.contains(teamA) && ids.contains(teamB)
        }
    }

    // ── Hidden achievement detectors ──

    /// Whether the user has visited a specific ballpark by its slug id.
    private func visitedPark(_ id: String) -> Bool {
        visitedBallparkIds.contains(id)
    }

    /// Visited Fenway, Wrigley, AND Dodger Stadium — the three classic parks.
    private var classicTrio: Bool {
        let trio: Set<String> = ["fenway-park", "wrigley-field", "dodger-stadium"]
        return trio.isSubset(of: visitedBallparkIds)
    }

    /// Witnessed a blowout of 15+ runs.
    private var witnessedBlowout15: Bool {
        completedGames.contains { abs($0.homeScore - $0.awayScore) >= 15 }
    }

    /// Saw a no-hitter (from milestones).
    private var witnessedNoHitter: Bool {
        completedGames.flatMap(\.milestones).contains { $0.category == .noHitter }
    }

    /// Saw a perfect game (from milestones).
    private var witnessedPerfectGame: Bool {
        completedGames.flatMap(\.milestones).contains {
            $0.category == .noHitter && $0.title == "Perfect Game"
        }
    }

    /// Saw a player hit for the cycle (from milestones).
    private var witnessedCycle: Bool {
        completedGames.flatMap(\.milestones).contains { $0.category == .cycle }
    }

    /// Saw a specific career home-run milestone (e.g. 500, 600).
    private func witnessedFamousHRMark(_ hr: Int) -> Bool {
        completedGames.flatMap(\.milestones).contains { m in
            m.category == .homeRun && m.stat.contains("#\(hr)")
        }
    }

    /// Witnessed a 3,000th career hit.
    private var witnessed3000Hit: Bool {
        completedGames.flatMap(\.milestones).contains { m in
            m.category == .hits && (m.stat.contains("3000") || m.title.contains("3000"))
        }
    }

    /// Saw a pitcher strike out 300+ batters (career milestone, not game).
    private var witnessed300KStrikeoutGame: Bool {
        completedGames.flatMap(\.highlights).contains { h in
            h.kind == .pitching && h.description.contains("K") &&
            (h.description.contains("300") || h.description.contains("15 K") || h.description.contains("16 K") || h.description.contains("17 K") || h.description.contains("18 K") || h.description.contains("19 K") || h.description.contains("20 K"))
        }
    }

    /// Saw a grand slam live.
    private var witnessedGrandSlam: Bool {
        completedGames.flatMap(\.highlights).contains { h in
            h.description.lowercased().contains("grand slam")
        }
    }

    /// Saw an inside-the-park home run.
    private var witnessedInsideTheParkHR: Bool {
        completedGames.flatMap(\.highlights).contains { h in
            h.description.lowercased().contains("inside the park")
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
        if let cached = cachedVisitedParkSequence, statsCacheGameCount == games.count {
            return cached
        }
        let chrono = completedGames.sorted { $0.date < $1.date }
        var seen: Set<String> = []
        let result = chrono.compactMap { game -> Ballpark? in
            guard !seen.contains(game.ballparkId) else { return nil }
            seen.insert(game.ballparkId)
            return game.ballpark
        }
        if games.count > 100 {
            cachedVisitedParkSequence = result
            statsCacheGameCount = games.count
        }
        return result
    }

    // MARK: - Canonical identity

    /// Calendar day + hour bucket + home team + away team uniquely identifies
    /// a game. Used for dedup across shared imports and manual entries.
    /// Including the hour lets doubleheaders (same day, same teams) coexist.
    private func canonicalKey(_ game: AttendedGame) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour], from: game.date)
        let ids = [game.homeTeamId, game.awayTeamId].sorted().joined(separator: "-")
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(c.hour ?? 0)-\(ids)"
    }

    /// Check whether a game with this identity already exists in the diary.
    /// Uses day + teams only (no hour) for backward-compatible lookup.
    func hasGame(day: Date, homeTeamId: String, awayTeamId: String) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: day)
        let ids = [homeTeamId, awayTeamId].sorted().joined(separator: "-")
        let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(ids)"
        return games.contains { g in
            let gc = cal.dateComponents([.year, .month, .day], from: g.date)
            let gIds = [g.homeTeamId, g.awayTeamId].sorted().joined(separator: "-")
            return "\(gc.year ?? 0)-\(gc.month ?? 0)-\(gc.day ?? 0)-\(gIds)" == key
        }
    }

    // MARK: - Fuzzy duplicate detection

    /// Scans the existing diary for entries that are suspiciously similar to
    /// this candidate — same ballpark within a day, or matching confirmation
    /// number. Returns the best-matching existing game, or nil.
    func findNearDuplicate(for candidate: NearDuplicateCandidate) -> AttendedGame? {
        let cal = Calendar(identifier: .gregorian)

        // Strongest signal: same confirmation number on a different game.
        if let conf = candidate.confirmation, !conf.trimmingCharacters(in: .whitespaces).isEmpty {
            if let match = games.first(where: { $0.confirmation == conf && $0.id != candidate.proposedId }) {
                return match
            }
        }

        // Same ballpark + same matchup within ±1 day (possible date-parsing
        // variance). Consecutive-day games of the same series are the most
        // common fan pattern, so we require the SAME two teams to match.
        let candidateDay = cal.startOfDay(for: candidate.date)
        let candidateTeams = Set([candidate.homeTeamId, candidate.awayTeamId])
        for game in games where game.ballparkId == candidate.ballparkId && game.id != candidate.proposedId {
            let gameTeams = Set([game.homeTeamId, game.awayTeamId])
            guard candidateTeams == gameTeams else { continue }
            // If both games have confirmation numbers and they differ, treat
            // them as separate games even if teams match.
            if let gameConf = game.confirmation, !gameConf.trimmingCharacters(in: .whitespaces).isEmpty,
               let candConf = candidate.confirmation, !candConf.trimmingCharacters(in: .whitespaces).isEmpty,
               gameConf != candConf {
                continue
            }
            let gameDay = cal.startOfDay(for: game.date)
            let diff = abs(gameDay.timeIntervalSince(candidateDay))
            if diff <= 86400 { // ±1 day, same matchup
                return game
            }
        }

        // Same matchup within ±3 days (possible series overlap).
        for game in games where game.id != candidate.proposedId {
            let gameTeams = Set([game.homeTeamId, game.awayTeamId])
            guard candidateTeams == gameTeams else { continue }
            let gameDay = cal.startOfDay(for: game.date)
            let diff = abs(gameDay.timeIntervalSince(candidateDay))
            if diff <= 3 * 86400 { return game }
        }

        return nil
    }

    /// Add a flagged duplicate for user review.
    private func flagDuplicate(
        candidate: NearDuplicateCandidate,
        existingGame: AttendedGame,
        source: String
    ) {
        let flagged = FlaggedDuplicate(
            id: UUID(),
            candidateDate: candidate.date,
            candidateHomeTeamId: candidate.homeTeamId,
            candidateAwayTeamId: candidate.awayTeamId,
            candidateBallparkId: candidate.ballparkId,
            candidateConfirmation: candidate.confirmation,
            candidateSection: candidate.section,
            candidateRow: candidate.row,
            candidateSeat: candidate.seat,
            candidateSource: source,
            existingGameId: existingGame.id,
            detectedAt: .now
        )
        flaggedDuplicates.append(flagged)
        save()
    }

    /// Remove a flagged duplicate (the user chose to discard the new entry).
    func dismissFlaggedDuplicate(_ id: UUID) {
        flaggedDuplicates.removeAll { $0.id == id }
        save()
    }

    /// Accept a flagged duplicate: merge the candidate's seat + confirmation
    /// details into the existing game instead of replacing it with a zero-score
    /// shell. Preserves scores, status, enrichment, companions, and memory.
    /// If network is available, re-verifies against MLBStatsService before saving.
    func acceptFlaggedDuplicate(_ flagged: FlaggedDuplicate) {
        // Find the existing game and merge the candidate's seat details.
        guard let existing = game(id: flagged.existingGameId) else {
            flaggedDuplicates.removeAll { $0.id == flagged.id }
            save()
            return
        }

        // Merge seat info from the candidate if it has any.
        let mergedSeat = existing.withSeat(
            section: flagged.candidateSection.isEmpty ? existing.section : flagged.candidateSection,
            row: flagged.candidateRow.isEmpty ? existing.row : flagged.candidateRow,
            seat: flagged.candidateSeat.isEmpty ? existing.seat : flagged.candidateSeat
        )

        // Preserve the existing game's scores, status, enrichment, companions,
        // and memory — only update seat and confirmation from the candidate.
        var merged = AttendedGame(
            id: mergedSeat.id, date: mergedSeat.date, ballparkId: mergedSeat.ballparkId,
            homeTeamId: mergedSeat.homeTeamId, awayTeamId: mergedSeat.awayTeamId,
            homeScore: mergedSeat.homeScore, awayScore: mergedSeat.awayScore,
            userRootedForHome: mergedSeat.userRootedForHome,
            section: mergedSeat.section, row: mergedSeat.row, seat: mergedSeat.seat,
            confirmation: flagged.candidateConfirmation ?? mergedSeat.confirmation,
            weather: mergedSeat.weather, firstPitchTempF: mergedSeat.firstPitchTempF,
            attendance: mergedSeat.attendance, durationMinutes: mergedSeat.durationMinutes,
            highlights: mergedSeat.highlights, milestones: mergedSeat.milestones,
            pitching: mergedSeat.pitching,
            companions: mergedSeat.companions, memory: mergedSeat.memory,
            emailSubject: mergedSeat.emailSubject, source: mergedSeat.source,
            status: mergedSeat.status, isVerified: mergedSeat.isVerified
        )

        // Try to re-verify against the MLB schedule if the game is completed
        // and has valid team IDs.
        if !merged.isUpcoming {
            let homeMlbId = merged.homeTeam.mlbId
            let awayMlbId = merged.awayTeam.mlbId
            if homeMlbId > 0 {
                Task { @MainActor in
                    if let results = try? await MLBStatsService.shared.games(on: merged.date, teamMlbId: homeMlbId) {
                        let match = results.first {
                            ($0.homeMlbId == homeMlbId && $0.awayMlbId == awayMlbId) ||
                            ($0.awayMlbId == homeMlbId && $0.homeMlbId == awayMlbId)
                        }
                        if let match, match.isFinal,
                           let details = await MLBStatsService.shared.details(forGamePk: match.gamePk) {
                            merged = merged.enriched(with: details)
                        }
                    }
                    // Update the existing game in place.
                    self.replaceGame(merged)
                    self.flaggedDuplicates.removeAll { $0.id == flagged.id }
                    self.save()
                }
                return
            }
        }

        // No re-verification — just update the existing game.
        replaceGame(merged)
        flaggedDuplicates.removeAll { $0.id == flagged.id }
        save()
    }

    /// Replace a game in-place by ID, preserving its inbox location.
    private func replaceGame(_ updated: AttendedGame) {
        for (inboxId, list) in gamesByInbox {
            guard let index = list.firstIndex(where: { $0.id == updated.id }) else { continue }
            var newList = list
            newList[index] = updated
            gamesByInbox[inboxId] = newList.sorted { $0.date > $1.date }
            return
        }
    }

    /// Toggle automatic duplicate deletion. When on, near-duplicates are
    /// silently dropped without prompting the user.
    func toggleAutoDelete() {
        autoDeleteDuplicates.toggle()
        defaults.set(autoDeleteDuplicates, forKey: autoDeleteKey)
        // If turning on auto-delete, clean up any existing flagged duplicates.
        if autoDeleteDuplicates {
            flaggedDuplicates.removeAll()
            save()
        }
    }

    // MARK: Manual entries

    /// Add a manually entered game. Rejects exact duplicates by canonical key.
    /// Also checks for near-duplicates and either auto-deletes (if preference
    /// is on) or flags them for user review.
    /// Returns nil if a game with the same day + teams already exists, or if
    /// a near-duplicate was flagged instead of saved.
    @discardableResult
    func addManualGame(_ game: AttendedGame) -> AttendedGame? {
        let key = canonicalKey(game)
        let existingKeys = Set(games.map(canonicalKey))
        guard !existingKeys.contains(key) else { return nil }

        // Check for near-duplicates.
        let candidate = NearDuplicateCandidate(
            proposedId: game.id,
            date: game.date,
            homeTeamId: game.homeTeamId,
            awayTeamId: game.awayTeamId,
            ballparkId: game.ballparkId,
            confirmation: game.confirmation,
            section: game.section,
            row: game.row,
            seat: game.seat
        )
        if let conflict = findNearDuplicate(for: candidate) {
            if autoDeleteDuplicates {
                return nil
            } else {
                flagDuplicate(
                    candidate: candidate,
                    existingGame: conflict,
                    source: game.emailSubject
                )
                return nil
            }
        }

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

    /// Update which team the user rooted for on a saved game. Pass nil to
    /// mark the user as a neutral observer. Flips the win/loss outcome derived
    /// from `userWon` so stats stay correct.
    func setRootedForHome(_ id: UUID, rootedForHome: Bool?) {
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

    /// Update memory fields (companions and notes) for any game.
    func setMemory(_ id: UUID, companions: String, memory: String) {
        for (inboxId, list) in gamesByInbox {
            guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
            var updated = list
            updated[index] = updated[index].withMemory(companions: companions, memory: memory)
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

        var hadNetworkError = false
        let imported = await importSharedTickets()
        await refreshUpcomingScores(&hadNetworkError)
        await enrichExistingGames(&hadNetworkError)
        await reVerifyUnverifiedGames(&hadNetworkError)

        if hadNetworkError {
            lastRefreshError = "Couldn't reach MLB Stats — pull to retry"
        } else {
            lastRefreshError = nil
        }
        
        // If there are still upcoming games, schedule an extra check
        // a few minutes later to catch scores that post after the game.
        if !upcomingGames.isEmpty {
            // Cancel any previous follow-up before scheduling a new one.
            followUpRefreshTask?.cancel()
            followUpRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(180))
                guard !Task.isCancelled else { return }
                var dummy = false
                await refreshUpcomingScores(&dummy)
                save()
            }
        }
        
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

            // Check for near-duplicates (same ballpark ±1 day, same confirmation no., etc.)
            let nearDup = NearDuplicateCandidate(
                proposedId: game.id,
                date: game.date,
                homeTeamId: game.homeTeamId,
                awayTeamId: game.awayTeamId,
                ballparkId: game.ballparkId,
                confirmation: game.confirmation,
                section: game.section,
                row: game.row,
                seat: game.seat
            )
            if let conflict = findNearDuplicate(for: nearDup) {
                if autoDeleteDuplicates {
                    // Auto-delete is on — silently drop the near-duplicate.
                    continue
                } else {
                    // Flag it for user review instead of adding.
                    flagDuplicate(
                        candidate: nearDup,
                        existingGame: conflict,
                        source: game.emailSubject
                    )
                    continue
                }
            }

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
    private func refreshUpcomingScores(_ hadNetworkError: inout Bool) async {
        var didChange = false
        for (inboxId, list) in gamesByInbox {
            var updated = list
            for (index, game) in list.enumerated() where game.isUpcoming {
                let teamMlbId = game.homeTeam.mlbId
                let opponentMlbId = game.awayTeam.mlbId
                guard teamMlbId > 0 else { continue }
                let resultsResult = try? await MLBStatsService.shared.games(on: game.date, teamMlbId: teamMlbId)
                guard let results = resultsResult else {
                    hadNetworkError = true
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
    private func enrichExistingGames(_ hadNetworkError: inout Bool) async {
        var didChange = false
        for (inboxId, list) in gamesByInbox {
            var updated = list
            for (index, game) in list.enumerated() where !game.isUpcoming && !game.isEnriched {
                let teamMlbId = game.homeTeam.mlbId
                let opponentMlbId = game.awayTeam.mlbId
                guard teamMlbId > 0 else { continue }
                let resultsResult = try? await MLBStatsService.shared.games(on: game.date, teamMlbId: teamMlbId)
                guard let results = resultsResult else {
                    hadNetworkError = true
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
    private func reVerifyUnverifiedGames(_ hadNetworkError: inout Bool) async {
        var didChange = false
        for (inboxId, list) in gamesByInbox {
            var updated = list
            for (index, game) in list.enumerated() where !game.verified && !game.isUpcoming {
                let homeMlbId = game.homeTeam.mlbId
                let awayMlbId = game.awayTeam.mlbId
                guard homeMlbId > 0 else { continue }
                let resultsResult = try? await MLBStatsService.shared.games(on: game.date, teamMlbId: homeMlbId)
                guard let results = resultsResult else {
                    hadNetworkError = true
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
                            pitching: game.pitching,
                            companions: game.companions, memory: game.memory,
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
        flaggedDuplicates.removeAll()
        importAttempts.removeAll()
        lastRefreshAt = nil
        autoDeleteDuplicates = false
        favoriteTeamId = Team.yankees.id
        hasPickedFavorite = false
        hasCompletedOnboarding = false
        hasAcceptedTerms = false
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: autoDeleteKey)
        try? FileManager.default.removeItem(at: diaryFileURL)
    }

    // MARK: - Export / Import

    /// Export the diary as a JSON data blob for backup or transfer.
    func exportData() -> Data? {
        let snapshot = Snapshot(
            schemaVersion: Self.currentSchemaVersion,
            favoriteTeamId: favoriteTeamId,
            hasPickedFavorite: hasPickedFavorite,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasAcceptedTerms: hasAcceptedTerms,
            inboxes: connectedInboxes,
            gamesByInbox: Dictionary(uniqueKeysWithValues: gamesByInbox.map { ($0.key.uuidString, $0.value) }),
            droppedCandidates: droppedCandidates,
            flaggedDuplicates: flaggedDuplicates
        )
        return try? JSONEncoder().encode(snapshot)
    }

    /// Import a diary JSON blob, merging games by canonical key (dedup).
    /// Returns the number of newly imported games.
    @discardableResult
    func importData(_ data: Data) -> Int {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return 0 }
        var existingKeys = Set(games.map(canonicalKey))
        var newCount = 0
        for (key, games) in snapshot.gamesByInbox {
            guard let inboxId = UUID(uuidString: key) else { continue }
            var existing = gamesByInbox[inboxId] ?? []
            for game in games {
                let ck = canonicalKey(game)
                guard !existingKeys.contains(ck) else { continue }
                existingKeys.insert(ck)
                existing.append(game)
                newCount += 1
            }
            gamesByInbox[inboxId] = existing.sorted { $0.date > $1.date }
        }
        // Merge inboxes that don't already exist.
        for inbox in snapshot.inboxes where !connectedInboxes.contains(where: { $0.id == inbox.id }) {
            connectedInboxes.append(inbox)
        }
        if newCount > 0 { save() }
        return newCount
    }

    /// Season recap data for "Ballpark Wrapped" — per-year stats summary.
    struct SeasonRecap: Identifiable {
        let year: Int
        let gameCount: Int
        let wins: Int
        let losses: Int
        let parksVisited: Int
        let totalMinutes: Int
        let topMilestone: String?
        let bestGame: AttendedGame?

        var id: Int { year }

        var winPct: Double {
            let total = wins + losses
            guard total > 0 else { return 0 }
            return Double(wins) / Double(total)
        }
    }

    /// Build per-year season recaps for Ballpark Wrapped.
    var seasonRecaps: [SeasonRecap] {
        let grouped = Dictionary(grouping: completedGames) {
            Calendar.current.component(.year, from: $0.date)
        }
        return grouped.map { year, games in
            let rooted = games.filter { $0.userRootedForHome != nil }
            let wins = rooted.filter(\.userWon).count
            let losses = rooted.count - wins
            let parks = Set(games.map(\.ballparkId)).count
            let minutes = games.reduce(0) { $0 + $1.durationMinutes }
            let milestone = games.flatMap(\.milestones).first
            let bestGame = games.sorted { $0.totalRuns > $1.totalRuns }.first
            return SeasonRecap(
                year: year, gameCount: games.count,
                wins: wins, losses: losses,
                parksVisited: parks, totalMinutes: minutes,
                topMilestone: milestone.map { "\($0.title) — \($0.playerName)" },
                bestGame: bestGame
            )
        }.sorted { $0.year > $1.year }
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
        var schemaVersion: Int?
        var favoriteTeamId: String
        var hasPickedFavorite: Bool
        var hasCompletedOnboarding: Bool
        var hasAcceptedTerms: Bool
        var inboxes: [ConnectedInbox]
        var gamesByInbox: [String: [AttendedGame]]
        var droppedCandidates: [DroppedCandidate]
        var flaggedDuplicates: [FlaggedDuplicate]
    }

    /// Current schema version — bumped when the Snapshot format changes.
    private static let currentSchemaVersion: Int = 2

    private func save() {
        // Invalidate memoized stats caches — data changed.
        cachedAchievementList = nil
        cachedMilesTraveled = nil
        cachedVisitedParkSequence = nil

        let snapshot = Snapshot(
            schemaVersion: Self.currentSchemaVersion,
            favoriteTeamId: favoriteTeamId,
            hasPickedFavorite: hasPickedFavorite,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasAcceptedTerms: hasAcceptedTerms,
            inboxes: connectedInboxes,
            gamesByInbox: Dictionary(uniqueKeysWithValues: gamesByInbox.map { ($0.key.uuidString, $0.value) }),
            droppedCandidates: droppedCandidates,
            flaggedDuplicates: flaggedDuplicates
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Atomic write to the file in Application Support.
        do {
            try data.write(to: diaryFileURL, options: .atomic)
        } catch {
            // Fallback to UserDefaults if the file write fails.
            defaults.set(data, forKey: storageKey)
        }
    }

    private func load() {
        // 1. Try reading from the file in Application Support.
        if let data = try? Data(contentsOf: diaryFileURL) {
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                applySnapshot(snapshot)
                return
            } else {
                // File exists but is corrupt — back it up before overwriting.
                let backupURL = diaryFileURL.deletingPathExtension().appendingPathExtension("corrupt-backup.json")
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: diaryFileURL, to: backupURL)
            }
        }

        // 2. One-time migration from UserDefaults to the file.
        if let data = defaults.data(forKey: storageKey) {
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                applySnapshot(snapshot)
                // Write to the new file location and keep the old UserDefaults
                // blob as a backup (don't delete it — it's the safety net).
                if let encoded = try? JSONEncoder().encode(snapshot) {
                    try? encoded.write(to: diaryFileURL, options: .atomic)
                }
                return
            } else {
                // UserDefaults blob is corrupt — copy to a recovery key.
                defaults.set(data, forKey: "ballparkdiary.state.v2.corrupt-backup")
            }
        }

        // 3. First launch or all sources failed — fresh state.
    }

    /// Apply a decoded snapshot to the store's properties.
    private func applySnapshot(_ snapshot: Snapshot) {
        favoriteTeamId = snapshot.favoriteTeamId
        hasPickedFavorite = snapshot.hasPickedFavorite
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        hasAcceptedTerms = snapshot.hasAcceptedTerms
        connectedInboxes = snapshot.inboxes
        let pairs: [(UUID, [AttendedGame])] = snapshot.gamesByInbox.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        }
        gamesByInbox = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        droppedCandidates = snapshot.droppedCandidates
        flaggedDuplicates = snapshot.flaggedDuplicates
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

/// Input for fuzzy duplicate detection — the minimal fields needed to check
/// whether a candidate overlaps with an existing diary entry.
struct NearDuplicateCandidate {
    let proposedId: UUID
    let date: Date
    let homeTeamId: String
    let awayTeamId: String
    let ballparkId: String
    let confirmation: String?
    let section: String
    let row: String
    let seat: String
}

/// A potential duplicate entry flagged for user review. Shows both the
/// candidate (new) entry and the existing game it conflicts with.
struct FlaggedDuplicate: Identifiable, Codable, Hashable {
    let id: UUID
    let candidateDate: Date
    let candidateHomeTeamId: String
    let candidateAwayTeamId: String
    let candidateBallparkId: String
    let candidateConfirmation: String?
    let candidateSection: String
    let candidateRow: String
    let candidateSeat: String
    let candidateSource: String
    let existingGameId: UUID
    let detectedAt: Date

    var candidateHomeTeam: Team { Team.by(id: candidateHomeTeamId) ?? .yankees }
    var candidateAwayTeam: Team { Team.by(id: candidateAwayTeamId) ?? .redSox }
    var candidateBallpark: Ballpark { Ballpark.by(id: candidateBallparkId) ?? Ballpark.all[0] }

    /// Formatted matchup string for display.
    var matchupLabel: String {
        "\(candidateAwayTeam.abbreviation) @ \(candidateHomeTeam.abbreviation)"
    }

    /// Formatted date for display.
    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: candidateDate)
    }

    /// Whether the candidate has seat info worth showing.
    var hasSeatInfo: Bool {
        [candidateSection, candidateRow, candidateSeat].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
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
    /// Hidden achievements only appear in the grid once unlocked.
    /// They're the rare, stadium-specific, and surprise badges.
    var hidden: Bool = false

    enum Tier { case free, pro }
}
