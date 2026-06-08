import Foundation

/// A single MLB game the user attended, derived from a parsed email ticket.
struct AttendedGame: Identifiable, Hashable, Codable {
    let id: UUID
    let date: Date
    let ballparkId: String
    let homeTeamId: String
    let awayTeamId: String
    let homeScore: Int
    let awayScore: Int
    let userRootedForHome: Bool
    let section: String
    let row: String
    let seat: String
    let weather: Weather
    let firstPitchTempF: Int
    let attendance: Int
    let durationMinutes: Int
    let highlights: [Highlight]
    let milestones: [PlayerMilestone]
    let emailSubject: String   // surfaced during import (shared ticket / manual note)
    let source: String         // ticketing platform / receipt source
    /// Whether the game has been played (real final score) or is still upcoming
    /// (ticket for a future game — no score yet). Optional for backward-compatible
    /// decoding of diaries saved before this field existed (treated as completed).
    let status: Status?

    /// Resolved status, defaulting older saved games to `.completed`.
    var gameStatus: Status { status ?? .completed }
    /// A ticket for a game that hasn't been played yet — no real score exists.
    var isUpcoming: Bool { gameStatus == .upcoming }

    var ballpark: Ballpark { Ballpark.by(id: ballparkId) ?? Ballpark.all[0] }
    var homeTeam: Team { Team.by(id: homeTeamId) ?? .yankees }
    var awayTeam: Team { Team.by(id: awayTeamId) ?? .redSox }
    var totalRuns: Int { homeScore + awayScore }
    var winnerTeam: Team { homeScore > awayScore ? homeTeam : awayTeam }
    var userWon: Bool {
        let homeWon = homeScore > awayScore
        return userRootedForHome ? homeWon : !homeWon
    }
    var scoreString: String { isUpcoming ? "vs" : "\(awayScore) – \(homeScore)" }

    /// Promote an upcoming game to completed once its real final score is known.
    func completed(homeScore: Int, awayScore: Int) -> AttendedGame {
        AttendedGame(
            id: id, date: date, ballparkId: ballparkId,
            homeTeamId: homeTeamId, awayTeamId: awayTeamId,
            homeScore: homeScore, awayScore: awayScore,
            userRootedForHome: userRootedForHome,
            section: section, row: row, seat: seat,
            weather: weather, firstPitchTempF: firstPitchTempF,
            attendance: attendance, durationMinutes: durationMinutes,
            highlights: highlights, milestones: milestones,
            emailSubject: emailSubject, source: source, status: .completed
        )
    }

    enum Status: String, Codable { case completed, upcoming }

    enum Weather: String, CaseIterable, Codable {
        case clear = "Clear"
        case partlyCloudy = "Partly Cloudy"
        case cloudy = "Cloudy"
        case rain = "Rain Delay"
        case dome = "Dome"
        case night = "Night Clear"

        var symbol: String {
            switch self {
            case .clear: return "sun.max.fill"
            case .partlyCloudy: return "cloud.sun.fill"
            case .cloudy: return "cloud.fill"
            case .rain: return "cloud.rain.fill"
            case .dome: return "building.columns.fill"
            case .night: return "moon.stars.fill"
            }
        }
    }

    struct Highlight: Hashable, Codable {
        let inning: String      // "T7", "B9"
        let description: String // "Judge solo HR to deep CF (412 ft)"
        let kind: Kind
        enum Kind: String, Codable { case homeRun, hit, pitching, defense, walkoff }

        var symbol: String {
            switch kind {
            case .homeRun: return "baseball.fill"
            case .hit: return "figure.baseball"
            case .pitching: return "flame.fill"
            case .defense: return "shield.lefthalf.filled"
            case .walkoff: return "star.circle.fill"
            }
        }
    }
}

/// A career milestone reached by an MLB player during a game the user
/// attended. Sourced (in a future version) from the MLB Stats API; for now
/// surfaced from confirmed game data. Tapping a milestone opens a detail screen.
struct PlayerMilestone: Identifiable, Hashable, Codable {
    let id: UUID
    let playerName: String
    let teamId: String
    let title: String       // e.g. "300th Career Home Run"
    let category: Category
    let stat: String        // e.g. "HR #300"
    let detail: String      // longer description
    let context: String     // historical context ("Joined a club of 154 players...")
    let inning: String?     // optional inning marker

    var team: Team { Team.by(id: teamId) ?? .yankees }

    enum Category: String, Codable {
        case homeRun
        case hits
        case strikeouts
        case wins
        case steals
        case debut
        case noHitter
        case cycle
        case milestone

        var symbol: String {
            switch self {
            case .homeRun: return "baseball.diamond.fill"
            case .hits: return "figure.baseball"
            case .strikeouts: return "flame.fill"
            case .wins: return "trophy.fill"
            case .steals: return "figure.run"
            case .debut: return "sparkles"
            case .noHitter: return "hand.raised.fill"
            case .cycle: return "arrow.triangle.2.circlepath"
            case .milestone: return "star.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .homeRun: return "Home Run"
            case .hits: return "Hits"
            case .strikeouts: return "Strikeouts"
            case .wins: return "Wins"
            case .steals: return "Stolen Bases"
            case .debut: return "Debut"
            case .noHitter: return "No-Hitter"
            case .cycle: return "Cycle"
            case .milestone: return "Milestone"
            }
        }
    }
}

// MARK: - Building attended games from real data

extension AttendedGame {
    /// Build an attended game from a confirmed MLB Stats API result plus the
    /// originating ticket email. Score, teams, venue and date are real; seat
    /// details and rooting interest are best-effort from the user's profile.
    static func from(
        result: MLBGameResult,
        source: String,
        emailSubject: String,
        favoriteTeamId: String?
    ) -> AttendedGame? {
        guard
            let homeTeam = Team.by(mlbId: result.homeMlbId),
            let awayTeam = Team.by(mlbId: result.awayMlbId),
            let ballpark = Ballpark.by(teamId: homeTeam.id)
        else { return nil }

        let rootedForHome: Bool
        if favoriteTeamId == homeTeam.id {
            rootedForHome = true
        } else if favoriteTeamId == awayTeam.id {
            rootedForHome = false
        } else {
            rootedForHome = true
        }

        let weather: Weather = {
            switch ballpark.roof {
            case .dome: return .dome
            case .retractable, .open:
                return result.dayNight.lowercased() == "day" ? .clear : .night
            }
        }()

        // Only a finished game has a real score; an upcoming ticket has none yet.
        let isFinal = result.isFinal
        return AttendedGame(
            id: UUID(),
            date: result.date,
            ballparkId: ballpark.id,
            homeTeamId: homeTeam.id,
            awayTeamId: awayTeam.id,
            homeScore: isFinal ? result.homeScore : 0,
            awayScore: isFinal ? result.awayScore : 0,
            userRootedForHome: rootedForHome,
            section: "",
            row: "",
            seat: "",
            weather: weather,
            firstPitchTempF: 0,
            attendance: 0,
            durationMinutes: 0,
            highlights: [],
            milestones: [],
            emailSubject: emailSubject,
            source: source,
            status: isFinal ? .completed : .upcoming
        )
    }
}
