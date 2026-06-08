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

/// Fetches real, completed game results from the free public MLB Stats API to
/// enrich games detected in the user's inbox with the correct final score,
/// matchup and venue.
nonisolated final class MLBStatsService: Sendable {
    static let shared = MLBStatsService()
    private init() {}

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

        let (data, response) = try await URLSession.shared.data(from: url)
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

    private struct ScheduleResponse: Decodable { let dates: [DateBlock] }
    private struct DateBlock: Decodable { let games: [Game] }
    private struct Game: Decodable {
        let gamePk: Int
        let gameDate: String?
        let dayNight: String?
        let status: Status
        let teams: Teams
        let venue: Venue?
    }
    private struct Status: Decodable { let abstractGameState: String? }
    private struct Venue: Decodable { let name: String? }
    private struct Teams: Decodable { let home: Side; let away: Side }
    private struct Side: Decodable {
        let score: Int?
        let team: TeamRef
    }
    private struct TeamRef: Decodable { let id: Int? }
}
