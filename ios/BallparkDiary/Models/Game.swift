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
    /// true = rooted for home, false = rooted for away, nil = neutral observer.
    let userRootedForHome: Bool?
    let section: String
    let row: String
    let seat: String
    /// Order / confirmation number pulled from the real ticket — proof this is a
    /// purchased seat, not a random schedule match. Optional for backward-
    /// compatible decoding of diaries saved before this field existed.
    let confirmation: String?
    let weather: Weather
    let firstPitchTempF: Int
    let attendance: Int
    let durationMinutes: Int
    let highlights: [Highlight]
    let milestones: [PlayerMilestone]
    let pitching: [PitchingLine]
    /// Who the user went to the game with (e.g. "Dad", "Sarah and Mike").
    let companions: String
    /// Free-form notes about the day — memories, moments, anything worth keeping.
    let memory: String
    let emailSubject: String   // surfaced during import (shared ticket / manual note)
    let source: String         // ticketing platform / receipt source
    /// Whether the game has been played (real final score) or is still upcoming
    /// (ticket for a future game — no score yet). Optional for backward-compatible
    /// decoding of diaries saved before this field existed (treated as completed).
    let status: Status?
    /// Whether this game was confirmed against the real MLB box score.
    /// nil for backward-compatible decoding of older saves (treated as verified).
    let isVerified: Bool?

    /// Resolved status, defaulting older saved games to `.completed`.
    var gameStatus: Status { status ?? .completed }
    /// Whether verified against the real box score. Legacy saves default to true.
    var verified: Bool { isVerified ?? true }
    /// A ticket for a game that hasn't been played yet — no real score exists.
    var isUpcoming: Bool { gameStatus == .upcoming }

    var ballpark: Ballpark { Ballpark.by(id: ballparkId) ?? Ballpark.all[0] }
    var homeTeam: Team { Team.by(id: homeTeamId) ?? .yankees }
    var awayTeam: Team { Team.by(id: awayTeamId) ?? .redSox }
    var totalRuns: Int { homeScore + awayScore }
    var winnerTeam: Team { homeScore > awayScore ? homeTeam : awayTeam }
    var userWon: Bool {
        guard let rootedForHome = userRootedForHome else { return false }
        let homeWon = homeScore > awayScore
        return rootedForHome ? homeWon : !homeWon
    }
    /// The team the user was rooting for, if any.
    var rootedTeam: Team? {
        guard let rootedForHome = userRootedForHome else { return nil }
        return rootedForHome ? homeTeam : awayTeam
    }
    var scoreString: String { isUpcoming ? "vs" : "\(awayScore) – \(homeScore)" }

    /// Confirmation number to surface, if the ticket carried one.
    var confirmationNumber: String? {
        guard let confirmation, !confirmation.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return confirmation
    }
    /// Whether we have any real seat location from the ticket.
    var hasSeatInfo: Bool {
        [section, row, seat].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "—" }
    }

    /// Whether the user has added personal memories to this game.
    var hasMemory: Bool {
        !companions.trimmingCharacters(in: .whitespaces).isEmpty
        || !memory.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True once verified box-score facts have been merged in. Used to decide
    /// whether a pull-to-refresh should re-fetch a game's details.
    var isEnriched: Bool { durationMinutes > 0 || !highlights.isEmpty || !milestones.isEmpty }

    /// Return a copy with updated seat information.
    func withSeat(section: String, row: String, seat: String) -> AttendedGame {
        AttendedGame(
            id: id, date: date, ballparkId: ballparkId,
            homeTeamId: homeTeamId, awayTeamId: awayTeamId,
            homeScore: homeScore, awayScore: awayScore,
            userRootedForHome: userRootedForHome,
            section: section, row: row, seat: seat, confirmation: confirmation,
            weather: weather, firstPitchTempF: firstPitchTempF,
            attendance: attendance, durationMinutes: durationMinutes,
            highlights: highlights, milestones: milestones, pitching: pitching,
            companions: companions, memory: memory,
            emailSubject: emailSubject, source: source, status: status,
            isVerified: isVerified
        )
    }

    /// Return a copy with updated memory fields.
    func withMemory(companions: String, memory: String) -> AttendedGame {
        AttendedGame(
            id: id, date: date, ballparkId: ballparkId,
            homeTeamId: homeTeamId, awayTeamId: awayTeamId,
            homeScore: homeScore, awayScore: awayScore,
            userRootedForHome: userRootedForHome,
            section: section, row: row, seat: seat, confirmation: confirmation,
            weather: weather, firstPitchTempF: firstPitchTempF,
            attendance: attendance, durationMinutes: durationMinutes,
            highlights: highlights, milestones: milestones, pitching: pitching,
            companions: companions, memory: memory,
            emailSubject: emailSubject, source: source, status: status,
            isVerified: isVerified
        )
    }

    /// Return a copy with the user's rooting interest changed to the given side.
    /// Pass nil to indicate neutral (rooting for neither team).
    func rooting(forHome rootedForHome: Bool?) -> AttendedGame {
        AttendedGame(
            id: id, date: date, ballparkId: ballparkId,
            homeTeamId: homeTeamId, awayTeamId: awayTeamId,
            homeScore: homeScore, awayScore: awayScore,
            userRootedForHome: rootedForHome,
            section: section, row: row, seat: seat, confirmation: confirmation,
            weather: weather, firstPitchTempF: firstPitchTempF,
            attendance: attendance, durationMinutes: durationMinutes,
            highlights: highlights, milestones: milestones, pitching: pitching,
            companions: companions, memory: memory,
            emailSubject: emailSubject, source: source, status: status,
            isVerified: isVerified
        )
    }

    /// Promote an upcoming game to completed once its real final score is known.
    func completed(homeScore: Int, awayScore: Int) -> AttendedGame {
        AttendedGame(
            id: id, date: date, ballparkId: ballparkId,
            homeTeamId: homeTeamId, awayTeamId: awayTeamId,
            homeScore: homeScore, awayScore: awayScore,
            userRootedForHome: userRootedForHome,
            section: section, row: row, seat: seat, confirmation: confirmation,
            weather: weather, firstPitchTempF: firstPitchTempF,
            attendance: attendance, durationMinutes: durationMinutes,
            highlights: highlights, milestones: milestones, pitching: pitching,
            companions: companions, memory: memory,
            emailSubject: emailSubject, source: source, status: .completed,
            isVerified: true
        )
    }

    /// Merge verified facts, scoring-play highlights and detected milestones from
    /// the MLB live feed into this game. Only applies to finished games.
    func enriched(with details: GameDetails) -> AttendedGame {
        guard !isUpcoming else { return self }
        let resolvedWeather = AttendedGame.weather(
            condition: details.weatherCondition,
            dayNight: details.dayNight,
            roof: ballpark.roof
        )
        return AttendedGame(
            id: id, date: date, ballparkId: ballparkId,
            homeTeamId: homeTeamId, awayTeamId: awayTeamId,
            homeScore: homeScore, awayScore: awayScore,
            userRootedForHome: userRootedForHome,
            section: section, row: row, seat: seat, confirmation: confirmation,
            weather: resolvedWeather ?? weather,
            firstPitchTempF: details.tempF > 0 ? details.tempF : firstPitchTempF,
            attendance: details.attendance > 0 ? details.attendance : attendance,
            durationMinutes: details.durationMinutes > 0 ? details.durationMinutes : durationMinutes,
            highlights: AttendedGame.highlights(from: details),
            milestones: AttendedGame.milestones(from: details),
            pitching: details.pitching,
            companions: companions, memory: memory,
            emailSubject: emailSubject, source: source, status: .completed,
            isVerified: true
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
            case .homeRun: return "baseball.fill"
            case .hits: return "figure.baseball"
            case .strikeouts: return "flame.fill"
            case .wins: return "trophy.fill"
            case .steals: return "figure.run"
            case .debut: return "sparkles"
            case .noHitter: return "hand.raised.fill"
            case .cycle: return "arrow.triangle.2.circlepath"
            case .milestone: return "rosette"
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

// MARK: - Deriving highlights & milestones from the live feed

extension AttendedGame {
    /// Career home-run totals worth flagging — every century mark plus historic
    /// milestones (660 Mays, 700, 714 Ruth, 755 Aaron, 762 Bonds). Lower
    /// thresholds catch early-career and mid-career achievements too.
    private static let famousHomeRunMarks: [Int] = [
        100, 200, 300, 400, 500, 600, 660, 700, 714, 755, 762, 800
    ]
    /// Career hits milestones worth flagging.
    private static let famousHitMarks: [Int] = [2000, 3000, 4000]
    /// Career wins milestones for pitchers.
    private static let famousWinMarks: [Int] = [100, 200, 300, 400]
    /// Career saves milestones for closers.
    private static let famousSaveMarks: [Int] = [200, 300, 400, 500, 600]
    /// Career strikeout milestones.
    private static let famousStrikeoutMarks: [Int] = [2000, 3000, 4000, 5000]

    static func weather(condition: String, dayNight: String, roof: Ballpark.RoofType) -> Weather? {
        if roof == .dome { return .dome }
        let c = condition.lowercased()
        if c.contains("roof closed") || c.contains("dome") { return .dome }
        if c.contains("rain") || c.contains("drizzle") || c.contains("shower") { return .rain }
        if c.contains("cloud") || c.contains("overcast") {
            return c.contains("partly") ? .partlyCloudy : .cloudy
        }
        // Clear / sunny / fair
        return dayNight.lowercased() == "day" ? .clear : .night
    }

    private static func inningLabel(half: String, inning: Int) -> String {
        (half == "bottom" ? "B" : "T") + "\(inning)"
    }

    static func highlights(from details: GameDetails) -> [Highlight] {
        var result: [Highlight] = []
        for play in details.scoringPlays {
            let isHR = play.event.lowercased().contains("home run")
            result.append(Highlight(
                inning: inningLabel(half: play.halfInning, inning: play.inning),
                description: play.description,
                kind: isHR ? .homeRun : .hit
            ))
        }
        // Surface dominant pitching lines (complete games or 10+ strikeouts).
        for line in details.pitching where line.completeGames >= 1 || line.strikeOuts >= 10 {
            let summary = "\(line.name): \(line.inningsPitched) IP, \(line.hits) H, \(line.runs) R, \(line.strikeOuts) K on \(line.pitches) pitches"
            result.append(Highlight(inning: "P", description: summary, kind: .pitching))
        }
        return result
    }

    static func milestones(from details: GameDetails) -> [PlayerMilestone] {
        var result: [PlayerMilestone] = []

        // Career home-run milestones (exact total verified against career logs).
        for hr in details.homeRuns {
            guard let total = hr.careerHomeRunTotal, total > 0 else { continue }
            let teamId = Team.by(mlbId: hr.battingTeamMlbId)?.id ?? ""
            let inning = inningLabel(half: hr.halfInning, inning: hr.inning)
            let grandSlamNote = hr.rbi >= 4 ? " (grand slam)" : ""

            if famousHomeRunMarks.contains(total) {
                result.append(PlayerMilestone(
                    id: UUID(), playerName: hr.batter, teamId: teamId,
                    title: "\(ordinal(total)) Career Home Run",
                    category: .homeRun, stat: "HR #\(total)",
                    detail: hr.description + grandSlamNote,
                    context: "You were there for \(hr.batter)'s \(ordinal(total)) career home run.",
                    inning: inning
                ))
            } else if let mark = famousHomeRunMarks.first(where: { $0 > total && $0 - total <= 10 }) {
                let away = mark - total
                result.append(PlayerMilestone(
                    id: UUID(), playerName: hr.batter, teamId: teamId,
                    title: "Career HR #\(total) — Chasing \(mark)",
                    category: .homeRun, stat: "HR #\(total)",
                    detail: hr.description + grandSlamNote,
                    context: "\(hr.batter)'s \(ordinal(total)) career home run — now just \(away) away from \(mark). You saw the chase live.",
                    inning: inning
                ))
            }
        }

        // Pitching gems from complete games, high-strikeout outings,
        // and career milestones (wins, saves, strikeouts).
        for line in details.pitching {
            let teamId = Team.by(mlbId: line.teamMlbId)?.id ?? ""
            let isCompleteGame = line.completeGames >= 1
            let isShutout = line.shutouts >= 1 || (isCompleteGame && line.runs == 0)

            // Game-level pitching achievements
            if isCompleteGame {
                let noHitter = line.hits == 0
                let perfect = noHitter && line.walks == 0 && line.hitBatsmen == 0
                let maddux = isShutout && (1..<100).contains(line.pitches)

                let title: String
                let category: PlayerMilestone.Category
                if perfect {
                    title = "Perfect Game"; category = .noHitter
                } else if noHitter {
                    title = "No-Hitter"; category = .noHitter
                } else if maddux {
                    title = "Maddux — Sub-100-Pitch Shutout"; category = .milestone
                } else if isShutout {
                    title = "Complete-Game Shutout"; category = .milestone
                } else {
                    title = "\(line.hits)-Hit Complete Game"; category = .milestone
                }

                let pieces = "\(line.inningsPitched) IP, \(line.hits) H, \(line.runs) R, \(line.walks) BB, \(line.strikeOuts) K on \(line.pitches) pitches"
                result.append(PlayerMilestone(
                    id: UUID(), playerName: line.name, teamId: teamId,
                    title: title, category: category,
                    stat: pieces,
                    detail: "\(line.name) went the distance: \(pieces).",
                    context: maddux
                        ? "A Maddux: a complete-game shutout on under 100 pitches. One of the rarest feats in baseball."
                        : "A complete game is rare these days. You saw every pitch.",
                    inning: nil
                ))
            } else if line.strikeOuts >= 12 {
                let elite = line.strikeOuts >= 15
                result.append(PlayerMilestone(
                    id: UUID(), playerName: line.name, teamId: teamId,
                    title: "\(line.strikeOuts)-Strikeout Game",
                    category: .strikeouts,
                    stat: "\(line.strikeOuts) K in \(line.inningsPitched) IP",
                    detail: "\(line.name) racked up \(line.strikeOuts) strikeouts.",
                    context: elite
                        ? "15 strikeouts in a single game is elite. You were in the building."
                        : "\(line.strikeOuts) strikeouts in one game is a night to remember.",
                    inning: nil
                ))
            }

            // Career pitching milestones (wins, saves, strikeouts)
            if let careerW = line.careerWins, careerW > 0 {
                if famousWinMarks.contains(careerW) {
                    result.append(PlayerMilestone(
                        id: UUID(), playerName: line.name, teamId: teamId,
                        title: "\(ordinal(careerW)) Career Win",
                        category: .wins,
                        stat: "Win #\(careerW)",
                        detail: "\(line.name) earned \(ordinal(careerW)) career win — \(line.inningsPitched) IP, \(line.hits) H, \(line.earnedRuns) ER.",
                        context: "Only a handful of pitchers reach \(careerW) wins. You saw history on the mound.",
                        inning: nil
                    ))
                } else if let mark = famousWinMarks.first(where: { $0 > careerW && $0 - careerW <= 5 }) {
                    result.append(PlayerMilestone(
                        id: UUID(), playerName: line.name, teamId: teamId,
                        title: "Career Win #\(careerW) — \(mark - careerW) to \(mark)",
                        category: .wins,
                        stat: "Win #\(careerW)",
                        detail: "\(line.name) is closing in on \(mark) career wins.",
                        context: "\(line.name) now has \(careerW) wins. You saw the journey.",
                        inning: nil
                    ))
                }
            }
            if let careerSv = line.careerSaves, careerSv > 0 {
                if famousSaveMarks.contains(careerSv) {
                    result.append(PlayerMilestone(
                        id: UUID(), playerName: line.name, teamId: teamId,
                        title: "\(ordinal(careerSv)) Career Save",
                        category: .milestone,
                        stat: "Save #\(careerSv)",
                        detail: "\(line.name) notched \(ordinal(careerSv)) career save.",
                        context: "The save became an official stat in 1969. Only a select group reaches \(careerSv).",
                        inning: nil
                    ))
                } else if let mark = famousSaveMarks.first(where: { $0 > careerSv && $0 - careerSv <= 5 }) {
                    result.append(PlayerMilestone(
                        id: UUID(), playerName: line.name, teamId: teamId,
                        title: "Save #\(careerSv) — \(mark - careerSv) to \(mark)",
                        category: .milestone,
                        stat: "Save #\(careerSv)",
                        detail: "\(line.name) is \(mark - careerSv) saves from the \(mark)-save club.",
                        context: "\(line.name) is chasing the elite \(mark)-save milestone.",
                        inning: nil
                    ))
                }
            }
            if let careerK = line.careerStrikeouts, careerK > 0 {
                if famousStrikeoutMarks.contains(careerK) {
                    result.append(PlayerMilestone(
                        id: UUID(), playerName: line.name, teamId: teamId,
                        title: "\(ordinal(careerK)) Career Strikeout",
                        category: .strikeouts,
                        stat: "K #\(careerK)",
                        detail: "\(line.name) recorded \(ordinal(careerK)) career strikeout.",
                        context: "\(careerK)+ strikeouts puts \(line.name) among the game's all-time greats.",
                        inning: nil
                    ))
                } else if let mark = famousStrikeoutMarks.first(where: { $0 > careerK && $0 - careerK <= 10 }) {
                    result.append(PlayerMilestone(
                        id: UUID(), playerName: line.name, teamId: teamId,
                        title: "Strikeout #\(careerK) — \(mark - careerK) to \(mark)",
                        category: .strikeouts,
                        stat: "K #\(careerK)",
                        detail: "\(line.name) is \(mark - careerK) Ks from \(mark) career strikeouts.",
                        context: "\(line.name) is on the doorstep of the \(mark)-K club.",
                        inning: nil
                    ))
                }
            }
        }

        return result
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10, tens = (n / 10) % 10
        if tens == 1 { suffix = "th" }
        else {
            switch ones { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" }
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Building attended games from real data

extension AttendedGame {
    /// Build an attended game from a confirmed MLB Stats API result with an
    /// explicitly known ballpark — used by the photo locator, where GPS pins
    /// the exact stadium (including neutral / international venues that aren't a
    /// home team's regular park, e.g. London Stadium or Tokyo Dome).
    static func from(
        result: MLBGameResult,
        ballpark: Ballpark,
        source: String,
        emailSubject: String,
        favoriteTeamId: String?
    ) -> AttendedGame? {
        guard
            let homeTeam = Team.by(mlbId: result.homeMlbId),
            let awayTeam = Team.by(mlbId: result.awayMlbId)
        else { return nil }

        let rootedForHome: Bool?
        if favoriteTeamId == homeTeam.id {
            rootedForHome = true
        } else if favoriteTeamId == awayTeam.id {
            rootedForHome = false
        } else {
            rootedForHome = nil
        }

        let weather: Weather = {
            switch ballpark.roof {
            case .dome: return .dome
            case .retractable, .open:
                return result.dayNight.lowercased() == "day" ? .clear : .night
            }
        }()

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
            section: "", row: "", seat: "",
            confirmation: nil,
            weather: weather,
            firstPitchTempF: 0,
            attendance: 0,
            durationMinutes: 0,
            highlights: [],
            milestones: [],
            pitching: [],
            companions: "",
            memory: "",
            emailSubject: emailSubject,
            source: source,
            status: isFinal ? .completed : .upcoming,
            isVerified: true
        )
    }

    /// Build an attended game from a confirmed MLB Stats API result plus the
    /// originating ticket email. Score, teams, venue and date are real; seat
    /// details and rooting interest are best-effort from the user's profile.
    static func from(
        result: MLBGameResult,
        source: String,
        emailSubject: String,
        favoriteTeamId: String?,
        section: String = "",
        row: String = "",
        seat: String = "",
        confirmation: String? = nil
    ) -> AttendedGame? {
        guard
            let homeTeam = Team.by(mlbId: result.homeMlbId),
            let awayTeam = Team.by(mlbId: result.awayMlbId),
            let ballpark = Ballpark.by(teamId: homeTeam.id)
        else { return nil }

        let rootedForHome: Bool?
        if favoriteTeamId == homeTeam.id {
            rootedForHome = true
        } else if favoriteTeamId == awayTeam.id {
            rootedForHome = false
        } else {
            rootedForHome = nil  // neutral — neither team is the user's favorite
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
            section: section,
            row: row,
            seat: seat,
            confirmation: confirmation,
            weather: weather,
            firstPitchTempF: 0,
            attendance: 0,
            durationMinutes: 0,
            highlights: [],
            milestones: [],
            pitching: [],
            companions: "",
            memory: "",
            emailSubject: emailSubject,
            source: source,
            status: isFinal ? .completed : .upcoming,
            isVerified: true
        )
    }
}
