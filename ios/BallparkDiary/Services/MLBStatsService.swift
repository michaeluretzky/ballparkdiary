import Foundation

/// A real game result from the public MLB Stats API (statsapi.mlb.com).
/// No API key required. Sendable & isolation-free for off-main decoding.
nonisolated struct MLBGameResult: Sendable, Hashable {
    let gamePk: Int
    let date: Date
    let homeMlbId: Int
    let awayMlbId: Int
    let homeScore: Int
    let awayScore: Int
    let venueName: String
    let dayNight: String
    let isFinal: Bool
}

/// An upcoming (not yet final) home game at a team's ballpark — used to
/// entice a visit when a park is selected on the map.
nonisolated struct MLBUpcomingGame: Sendable, Hashable, Identifiable {
    let gamePk: Int
    let date: Date
    let opponentMlbId: Int
    /// The club's official box-office link for this exact game (mlb.tickets.com),
    /// straight from the MLB schedule feed — always the right game, no search.
    let officialTicketURL: URL?
    var id: Int { gamePk }
}

// MARK: - Rich game details (box score / live feed)

/// Verified facts and notable plays pulled from a finished game's live feed.
/// Everything here is real data from statsapi.mlb.com — attendance, duration,
/// weather, the scoring plays, and the pitching lines used to surface
/// milestones. Isolation-free so it decodes off the main actor; the UI model
/// objects (highlights / milestones) are assembled on the main actor.
nonisolated struct GameDetails: Sendable, Hashable {
    let attendance: Int
    let durationMinutes: Int
    let tempF: Int
    let weatherCondition: String
    let dayNight: String
    let homeMlbId: Int
    let awayMlbId: Int
    let scoringPlays: [ScoringPlay]
    let homeRuns: [HomeRunPlay]
    let pitching: [PitchingLine]
    let batting: [BattingLine]
}

nonisolated struct ScoringPlay: Sendable, Hashable {
    let inning: Int
    let halfInning: String   // "top" / "bottom"
    let event: String        // "Single", "Home Run", "Sacrifice Fly"
    let description: String
    let battingTeamMlbId: Int
}

nonisolated struct HomeRunPlay: Sendable, Hashable {
    let inning: Int
    let halfInning: String
    let batter: String
    let batterMlbId: Int
    let battingTeamMlbId: Int
    let rbi: Int
    let seasonHomeRunNumber: Int?      // the "(14)" in the play description
    let careerHomeRunTotal: Int?       // exact career total through this homer
    let description: String
}

/// A batter's line from a finished game's box score (AB R H RBI BB K).
nonisolated struct BattingLine: Sendable, Hashable, Codable {
    let name: String
    let playerMlbId: Int
    let teamMlbId: Int
    /// MLB batting-order code: "100" = leadoff starter, "401" = first sub in the 4 hole.
    let battingOrder: Int
    let position: String
    let atBats: Int
    let runs: Int
    let hits: Int
    let doubles: Int
    let triples: Int
    let homeRuns: Int
    let rbi: Int
    let walks: Int
    let strikeOuts: Int
    let stolenBases: Int

    /// Lineup slot 1–9 derived from the order code.
    var lineupSlot: Int { battingOrder / 100 }
    /// Entered mid-game (pinch hitter, pinch runner, defensive sub).
    var isSubstitute: Bool { battingOrder % 100 != 0 }
}

nonisolated struct PitchingLine: Sendable, Hashable, Codable {
    let name: String
    let playerMlbId: Int
    let teamMlbId: Int
    let inningsPitched: String
    let hits: Int
    let runs: Int
    let earnedRuns: Int
    let walks: Int
    let strikeOuts: Int
    let hitBatsmen: Int
    let homeRunsAllowed: Int
    let pitches: Int
    let battersFaced: Int
    let completeGames: Int
    let shutouts: Int
    let saves: Int
    let losses: Int
    let holds: Int
    let blownSaves: Int
    let isWinner: Bool
    let careerWins: Int?
    let careerSaves: Int?
    let careerStrikeouts: Int?
}

/// Fetches real, completed game results from the free public MLB Stats API to
/// enrich games detected in the user's inbox with the correct final score,
/// matchup and venue.
nonisolated final class MLBStatsService: Sendable {
    static let shared = MLBStatsService()
    private init() {}

    /// Dedicated session with tight timeouts so a slow or stalled MLB endpoint
    /// can't hang a refresh. The default `URLSession.shared` waits up to 60s per
    /// request, which — multiplied across the many lookups a refresh performs —
    /// can leave the diary spinning for minutes on a flaky connection.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Returns completed regular/postseason games on `date`, optionally filtered
    /// to a single team. Dates use the league's calendar day.
    func games(on date: Date, teamMlbId: Int?) async throws -> [MLBGameResult] {
        var components = URLComponents(string: "https://statsapi.mlb.com/api/v1/schedule")!
        var items = [
            URLQueryItem(name: "sportId", value: "1"),
            URLQueryItem(name: "date", value: Self.dateFormatter.string(from: date))
        ]
        if let teamMlbId, teamMlbId > 0 {
            items.append(URLQueryItem(name: "teamId", value: String(teamMlbId)))
        }
        components.queryItems = items
        guard let url = components.url else { return [] }

        let (data, response) = try await Self.session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []
        }
        let schedule = try JSONDecoder().decode(ScheduleResponse.self, from: data)
        return schedule.dates.flatMap { day in
            day.games.compactMap { game -> MLBGameResult? in
                guard
                    let home = game.teams.home.team.id,
                    let away = game.teams.away.team.id
                else { return nil }
                let state = game.status.abstractGameState ?? ""
                return MLBGameResult(
                    gamePk: game.gamePk,
                    date: Self.gameDate(from: game.gameDate) ?? date,
                    homeMlbId: home,
                    awayMlbId: away,
                    homeScore: game.teams.home.score ?? 0,
                    awayScore: game.teams.away.score ?? 0,
                    venueName: game.venue?.name ?? "",
                    dayNight: game.dayNight ?? "night",
                    isFinal: state.caseInsensitiveCompare("Final") == .orderedSame
                )
            }
        }
    }

    /// Upcoming home games at `teamMlbId`'s ballpark over the next `days`
    /// days, soonest first. Returns an empty array on any failure so the map
    /// card can simply hide the section.
    func upcomingHomeGames(teamMlbId: Int, days: Int = 45, limit: Int = 3) async -> [MLBUpcomingGame] {
        guard teamMlbId > 0 else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        let start = Date.now
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        var components = URLComponents(string: "https://statsapi.mlb.com/api/v1/schedule")!
        components.queryItems = [
            URLQueryItem(name: "sportId", value: "1"),
            URLQueryItem(name: "teamId", value: String(teamMlbId)),
            URLQueryItem(name: "startDate", value: Self.dateFormatter.string(from: start)),
            URLQueryItem(name: "endDate", value: Self.dateFormatter.string(from: end)),
            // Ask MLB to include official per-game ticket links in the response.
            URLQueryItem(name: "hydrate", value: "game(tickets)")
        ]
        guard
            let url = components.url,
            let (data, response) = try? await Self.session.data(from: url),
            (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
            let schedule = try? JSONDecoder().decode(ScheduleResponse.self, from: data)
        else { return [] }

        var games: [MLBUpcomingGame] = []
        for day in schedule.dates {
            for game in day.games {
                guard
                    let home = game.teams.home.team.id, home == teamMlbId,
                    let away = game.teams.away.team.id,
                    let date = Self.gameDate(from: game.gameDate),
                    date > start
                else { continue }
                let state = game.status.abstractGameState ?? ""
                guard state.caseInsensitiveCompare("Final") != .orderedSame else { continue }
                games.append(MLBUpcomingGame(
                    gamePk: game.gamePk,
                    date: date,
                    opponentMlbId: away,
                    officialTicketURL: Self.officialTicketURL(from: game.tickets)
                ))
            }
        }
        return Array(games.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// Fetch verified facts, scoring plays and pitching lines for a finished
    /// game's live feed. Returns nil on any network/parse failure so callers can
    /// fall back to the bare score. Home-run plays are annotated with the
    /// batter's exact career home-run total at the time, enabling milestone
    /// detection (e.g. "chasing 700").
    func details(forGamePk gamePk: Int) async -> GameDetails? {
        guard let url = URL(string: "https://statsapi.mlb.com/api/v1.1/game/\(gamePk)/feed/live") else {
            return nil
        }
        guard
            let (data, response) = try? await Self.session.data(from: url),
            (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
            let feed = try? JSONDecoder().decode(LiveFeed.self, from: data)
        else { return nil }

        let homeId = feed.gameData.teams.home.id ?? 0
        let awayId = feed.gameData.teams.away.id ?? 0
        let info = feed.gameData.gameInfo
        let weather = feed.gameData.weather

        var scoringPlays: [ScoringPlay] = []
        var homeRuns: [HomeRunPlay] = []
        var careerCache: [Int: Int] = [:]   // batterId -> career HR before this season

        let season = Calendar(identifier: .gregorian).component(
            .year,
            from: Self.gameDate(from: feed.gameData.datetime?.dateTime) ?? .now
        )

        for play in feed.liveData.plays.allPlays {
            guard let result = play.result, let about = play.about else { continue }
            let half = about.halfInning ?? "top"
            let inning = about.inning ?? 0
            let battingTeam = half == "bottom" ? homeId : awayId
            let isScoring = (result.rbi ?? 0) > 0 || (result.eventType == "home_run")
            let event = result.event ?? ""
            let desc = result.description ?? ""

            if isScoring, !desc.isEmpty {
                scoringPlays.append(ScoringPlay(
                    inning: inning, halfInning: half, event: event,
                    description: desc, battingTeamMlbId: battingTeam
                ))
            }

            if result.eventType == "home_run", let batter = play.matchup?.batter {
                let seasonNumber = Self.parseSeasonHomeRun(from: desc)
                var careerTotal: Int? = nil
                if let batterId = batter.id, let seasonNumber {
                    let before: Int
                    if let cached = careerCache[batterId] {
                        before = cached
                    } else {
                        before = await careerHomeRuns(playerId: batterId, beforeSeason: season)
                        careerCache[batterId] = before
                    }
                    if before > 0 { careerTotal = before + seasonNumber }
                }
                homeRuns.append(HomeRunPlay(
                    inning: inning, halfInning: half,
                    batter: batter.fullName ?? "", batterMlbId: batter.id ?? 0,
                    battingTeamMlbId: battingTeam, rbi: result.rbi ?? 1,
                    seasonHomeRunNumber: seasonNumber, careerHomeRunTotal: careerTotal,
                    description: desc
                ))
            }
        }

        var pitching: [PitchingLine] = []
        var batting: [BattingLine] = []
        let winnerId = feed.liveData.decisions?.winner?.id
        for (side, teamMlbId) in [(feed.liveData.boxscore.teams.away, awayId), (feed.liveData.boxscore.teams.home, homeId)] {
            for bid in side.batters ?? [] {
                guard
                    let player = side.players["ID\(bid)"],
                    let stat = player.stats?.batting,
                    let orderString = player.battingOrder,
                    let order = Int(orderString)
                else { continue }
                batting.append(BattingLine(
                    name: player.person?.fullName ?? "",
                    playerMlbId: bid,
                    teamMlbId: teamMlbId,
                    battingOrder: order,
                    position: player.position?.abbreviation ?? "",
                    atBats: stat.atBats ?? 0,
                    runs: stat.runs ?? 0,
                    hits: stat.hits ?? 0,
                    doubles: stat.doubles ?? 0,
                    triples: stat.triples ?? 0,
                    homeRuns: stat.homeRuns ?? 0,
                    rbi: stat.rbi ?? 0,
                    walks: stat.baseOnBalls ?? 0,
                    strikeOuts: stat.strikeOuts ?? 0,
                    stolenBases: stat.stolenBases ?? 0
                ))
            }
            for pid in side.pitchers {
                guard let player = side.players["ID\(pid)"], let stat = player.stats?.pitching else { continue }
                pitching.append(PitchingLine(
                    name: player.person?.fullName ?? "",
                    playerMlbId: pid,
                    teamMlbId: teamMlbId,
                    inningsPitched: stat.inningsPitched ?? "0",
                    hits: stat.hits ?? 0, runs: stat.runs ?? 0,
                    earnedRuns: stat.earnedRuns ?? 0,
                    walks: stat.baseOnBalls ?? 0, strikeOuts: stat.strikeOuts ?? 0,
                    hitBatsmen: stat.hitBatsmen ?? 0,
                    homeRunsAllowed: stat.homeRuns ?? 0,
                    pitches: stat.numberOfPitches ?? stat.pitchesThrown ?? 0,
                    battersFaced: stat.battersFaced ?? 0,
                    completeGames: stat.completeGames ?? 0,
                    shutouts: stat.shutouts ?? 0,
                    saves: stat.saves ?? 0,
                    losses: stat.losses ?? 0,
                    holds: stat.holds ?? 0,
                    blownSaves: stat.blownSaves ?? 0,
                    isWinner: winnerId != nil && pid == winnerId,
                    careerWins: nil, careerSaves: nil, careerStrikeouts: nil
                ))
            }
        }

        // Enrich notable pitchers with career totals for milestone detection.
        for i in pitching.indices {
            let line = pitching[i]
            let notable = line.isWinner || line.saves > 0 || line.strikeOuts >= 6 || line.completeGames >= 1
            guard notable else { continue }
            let totals = await careerPitchingTotals(playerId: line.playerMlbId, beforeSeason: season)
            let inGameWins: Int = line.isWinner ? 1 : 0
            pitching[i] = PitchingLine(
                name: line.name, playerMlbId: line.playerMlbId, teamMlbId: line.teamMlbId,
                inningsPitched: line.inningsPitched, hits: line.hits, runs: line.runs,
                earnedRuns: line.earnedRuns, walks: line.walks, strikeOuts: line.strikeOuts,
                hitBatsmen: line.hitBatsmen, homeRunsAllowed: line.homeRunsAllowed,
                pitches: line.pitches, battersFaced: line.battersFaced,
                completeGames: line.completeGames, shutouts: line.shutouts,
                saves: line.saves, losses: line.losses,
                holds: line.holds, blownSaves: line.blownSaves,
                isWinner: line.isWinner,
                careerWins: totals.wins > 0 ? totals.wins + inGameWins : nil,
                careerSaves: totals.saves > 0 ? totals.saves + line.saves : nil,
                careerStrikeouts: totals.strikeouts > 0 ? totals.strikeouts + line.strikeOuts : nil
            )
        }

        // Lineup order within each team: slot 1–9, subs after the starter they replaced.
        batting.sort {
            $0.teamMlbId != $1.teamMlbId ? $0.teamMlbId < $1.teamMlbId : $0.battingOrder < $1.battingOrder
        }

        return GameDetails(
            attendance: info?.attendance ?? 0,
            durationMinutes: info?.gameDurationMinutes ?? 0,
            tempF: Int(weather?.temp ?? "") ?? 0,
            weatherCondition: weather?.condition ?? "",
            dayNight: feed.gameData.datetime?.dayNight ?? "night",
            homeMlbId: homeId, awayMlbId: awayId,
            scoringPlays: scoringPlays, homeRuns: homeRuns, pitching: pitching,
            batting: batting
        )
    }

    /// Sum a player's regular-season home runs across every season *before*
    /// `season`, so adding the in-season home-run number gives the exact career
    /// total at the moment of a homer. Combined multi-stint rows (no team id)
    /// are skipped so traded-player seasons aren't double counted. Returns 0 if
    /// the lookup fails.
    private func careerHomeRuns(playerId: Int, beforeSeason season: Int) async -> Int {
        guard
            let url = URL(string: "https://statsapi.mlb.com/api/v1/people/\(playerId)/stats?stats=yearByYear&group=hitting"),
            let (data, _) = try? await Self.session.data(from: url),
            let response = try? JSONDecoder().decode(YearByYearResponse.self, from: data),
            let splits = response.stats.first?.splits
        else { return 0 }
        var total = 0
        for split in splits {
            guard split.sport?.id == 1, split.team?.id != nil else { continue }
            guard let year = Int(split.season ?? ""), year < season else { continue }
            total += split.stat?.homeRuns ?? 0
        }
        return total
    }

    /// Career pitching totals (wins, saves, strikeouts) accumulated *before*
    /// `season`, so the current-season game stats can be added on top. Returns
    /// zeros if the lookup fails.
    func careerPitchingTotals(playerId: Int, beforeSeason season: Int) async -> (wins: Int, saves: Int, strikeouts: Int) {
        guard
            let url = URL(string: "https://statsapi.mlb.com/api/v1/people/\(playerId)/stats?stats=yearByYear&group=pitching"),
            let (data, _) = try? await Self.session.data(from: url),
            let response = try? JSONDecoder().decode(YearByYearResponse.self, from: data),
            let splits = response.stats.first?.splits
        else { return (0, 0, 0) }
        var wins = 0, saves = 0, strikeouts = 0
        for split in splits {
            guard split.sport?.id == 1, split.team?.id != nil else { continue }
            guard let year = Int(split.season ?? ""), year < season else { continue }
            wins += split.stat?.wins ?? 0
            saves += split.stat?.saves ?? 0
            strikeouts += split.stat?.strikeOuts ?? 0
        }
        return (wins, saves, strikeouts)
    }

    /// Career hitting totals (hits, stolen bases) accumulated *before* `season`.
    func careerHittingTotals(playerId: Int, beforeSeason season: Int) async -> (hits: Int, stolenBases: Int) {
        guard
            let url = URL(string: "https://statsapi.mlb.com/api/v1/people/\(playerId)/stats?stats=yearByYear&group=hitting"),
            let (data, _) = try? await Self.session.data(from: url),
            let response = try? JSONDecoder().decode(YearByYearResponse.self, from: data),
            let splits = response.stats.first?.splits
        else { return (0, 0) }
        var hits = 0, stolenBases = 0
        for split in splits {
            guard split.sport?.id == 1, split.team?.id != nil else { continue }
            guard let year = Int(split.season ?? ""), year < season else { continue }
            hits += split.stat?.hits ?? 0
            stolenBases += split.stat?.stolenBases ?? 0
        }
        return (hits, stolenBases)
    }

    /// Pick the official box-office link from a game's hydrated ticket blocks.
    /// Prefers the mobile link, falls back to any entry that carries one.
    private static func officialTicketURL(from tickets: [TicketBlock]?) -> URL? {
        guard let tickets, !tickets.isEmpty else { return nil }
        let preferred = tickets.first { $0.ticketType == "mobile" } ?? tickets.first { $0.ticketLinks?.home != nil }
        guard
            let link = (preferred ?? tickets[0]).ticketLinks?.home,
            let url = URL(string: link),
            url.scheme == "https"
        else { return nil }
        return url
    }

    /// Parse the season home-run number from a play description such as
    /// "Albert Pujols homers (14) on a line drive...".
    private static func parseSeasonHomeRun(from description: String) -> Int? {
        guard
            let regex = try? NSRegularExpression(pattern: "homers?\\s*\\((\\d+)\\)", options: .caseInsensitive),
            let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
            let range = Range(match.range(at: 1), in: description)
        else { return nil }
        return Int(description[range])
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func gameDate(from string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatter.date(from: string)
    }

    // MARK: - Decodable DTOs

    // Live feed DTOs
    private struct LiveFeed: Decodable {
        let gameData: GameDataBlock
        let liveData: LiveDataBlock
    }
    private struct GameDataBlock: Decodable {
        let teams: FeedTeams
        let weather: WeatherBlock?
        let gameInfo: GameInfoBlock?
        let datetime: DateTimeBlock?
    }
    private struct FeedTeams: Decodable { let home: FeedTeam; let away: FeedTeam }
    private struct FeedTeam: Decodable { let id: Int? }
    private struct WeatherBlock: Decodable { let condition: String?; let temp: String?; let wind: String? }
    private struct GameInfoBlock: Decodable { let attendance: Int?; let gameDurationMinutes: Int? }
    private struct DateTimeBlock: Decodable { let dateTime: String?; let dayNight: String? }
    private struct LiveDataBlock: Decodable {
        let plays: PlaysBlock
        let boxscore: BoxscoreBlock
        let decisions: DecisionsBlock?
    }
    private struct DecisionsBlock: Decodable { let winner: PersonRef? }
    private struct PersonRef: Decodable { let id: Int?; let fullName: String? }
    private struct PlaysBlock: Decodable { let allPlays: [PlayBlock] }
    private struct PlayBlock: Decodable {
        let result: PlayResult?
        let about: PlayAbout?
        let matchup: PlayMatchup?
    }
    private struct PlayResult: Decodable {
        let event: String?
        let eventType: String?
        let description: String?
        let rbi: Int?
    }
    private struct PlayAbout: Decodable { let halfInning: String?; let inning: Int? }
    private struct PlayMatchup: Decodable { let batter: PersonRef? }
    private struct BoxscoreBlock: Decodable { let teams: BoxscoreTeams }
    private struct BoxscoreTeams: Decodable { let home: BoxscoreSide; let away: BoxscoreSide }
    private struct BoxscoreSide: Decodable {
        let pitchers: [Int]
        let batters: [Int]?
        let players: [String: BoxscorePlayer]
    }
    private struct BoxscorePlayer: Decodable {
        let person: PersonRef?
        let stats: PlayerStats?
        let battingOrder: String?
        let position: PositionRef?
    }
    private struct PositionRef: Decodable { let abbreviation: String? }
    private struct PlayerStats: Decodable {
        let pitching: PitchingStat?
        let batting: BattingStat?
    }
    private struct BattingStat: Decodable {
        let atBats: Int?
        let runs: Int?
        let hits: Int?
        let doubles: Int?
        let triples: Int?
        let homeRuns: Int?
        let rbi: Int?
        let baseOnBalls: Int?
        let strikeOuts: Int?
        let stolenBases: Int?
    }
    private struct PitchingStat: Decodable {
        let inningsPitched: String?
        let hits: Int?
        let runs: Int?
        let earnedRuns: Int?
        let baseOnBalls: Int?
        let strikeOuts: Int?
        let hitBatsmen: Int?
        let homeRuns: Int?
        let numberOfPitches: Int?
        let pitchesThrown: Int?
        let battersFaced: Int?
        let completeGames: Int?
        let shutouts: Int?
        let saves: Int?
        let losses: Int?
        let holds: Int?
        let blownSaves: Int?
    }

    // Year-by-year hitting DTOs (career HR accumulation)
    private struct YearByYearResponse: Decodable { let stats: [StatGroup] }
    private struct StatGroup: Decodable { let splits: [YearSplit] }
    private struct YearSplit: Decodable {
        let season: String?
        let sport: SportRef?
        let team: TeamRefHR?
        let stat: CareerStat?
    }
    private struct SportRef: Decodable { let id: Int? }
    private struct TeamRefHR: Decodable { let id: Int? }
    /// Unified career stat covering both hitting and pitching year-by-year rows.
    /// The same JSON key "stat" carries different fields depending on the group
    /// parameter (hitting vs pitching), so every field is optional.
    private struct CareerStat: Decodable {
        let homeRuns: Int?
        let hits: Int?
        let stolenBases: Int?
        let wins: Int?
        let saves: Int?
        let strikeOuts: Int?
    }

    private struct ScheduleResponse: Decodable { let dates: [DateBlock] }
    private struct DateBlock: Decodable { let games: [Game] }
    private struct Game: Decodable {
        let gamePk: Int
        let gameDate: String?
        let dayNight: String?
        let status: Status
        let teams: Teams
        let venue: Venue?
        let tickets: [TicketBlock]?
    }
    private struct TicketBlock: Decodable {
        let ticketType: String?
        let ticketLinks: TicketLinks?
    }
    private struct TicketLinks: Decodable { let home: String? }
    private struct Status: Decodable { let abstractGameState: String? }
    private struct Venue: Decodable { let name: String? }
    private struct Teams: Decodable { let home: Side; let away: Side }
    private struct Side: Decodable {
        let score: Int?
        let team: TeamRef
    }
    private struct TeamRef: Decodable { let id: Int? }
}
