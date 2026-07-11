import Foundation

/// Conversion-driving derived stats: season counters, attendance streaks,
/// the "fan record" deep splits (by team, day/night, home/away), and the
/// free-milestone teaser used by the milestone paywall gate.
extension DiaryStore {

    // MARK: - Season counters & streaks

    /// Completed games attended in the current calendar year.
    var gamesThisSeason: Int {
        let year = Calendar.current.component(.year, from: .now)
        return completedGames.filter { Calendar.current.component(.year, from: $0.date) == year }.count
    }

    /// Consecutive seasons (calendar years) with at least one attended game,
    /// counting back from the most recent active season. The streak is only
    /// alive if that season is this year or last year (the season may not have
    /// started yet), otherwise it's 0.
    var seasonStreak: Int {
        let years = Set(completedGames.map { Calendar.current.component(.year, from: $0.date) })
        guard let latest = years.max() else { return 0 }
        let currentYear = Calendar.current.component(.year, from: .now)
        guard latest >= currentYear - 1 else { return 0 }
        var streak = 0
        var year = latest
        while years.contains(year) {
            streak += 1
            year -= 1
        }
        return streak
    }

    // MARK: - Fan record deep splits (Pro)

    /// Win-loss record for a single rooted-for team.
    struct TeamRecord: Identifiable {
        let team: Team
        let wins: Int
        let losses: Int
        var id: String { team.id }
        var games: Int { wins + losses }
        var winPct: Double { games > 0 ? Double(wins) / Double(games) : 0 }
    }

    /// A simple W-L split (day/night, home/away).
    struct RecordSplit {
        let label: String
        let wins: Int
        let losses: Int
        var games: Int { wins + losses }
    }

    /// The user's record broken down by the team they rooted for, most games first.
    var fanRecordByTeam: [TeamRecord] {
        var tally: [String: (w: Int, l: Int)] = [:]
        for g in rootedGames {
            guard let rooted = g.rootedTeam else { continue }
            var entry = tally[rooted.id] ?? (0, 0)
            if g.userWon { entry.w += 1 } else { entry.l += 1 }
            tally[rooted.id] = entry
        }
        return tally.compactMap { id, record in
            Team.by(id: id).map { TeamRecord(team: $0, wins: record.w, losses: record.l) }
        }
        .sorted { ($0.games, $0.winPct) > ($1.games, $1.winPct) }
    }

    /// Day-game vs night-game record (rooted games only). Dome/rain games are
    /// excluded since neither bucket applies cleanly.
    var dayNightSplits: [RecordSplit] {
        var day = (w: 0, l: 0), night = (w: 0, l: 0)
        for g in rootedGames {
            switch g.weather {
            case .clear, .partlyCloudy, .cloudy:
                if g.userWon { day.w += 1 } else { day.l += 1 }
            case .night:
                if g.userWon { night.w += 1 } else { night.l += 1 }
            case .dome, .rain:
                continue
            }
        }
        return [
            RecordSplit(label: "Day games", wins: day.w, losses: day.l),
            RecordSplit(label: "Night games", wins: night.w, losses: night.l),
        ]
    }

    /// Rooting-for-the-home-team vs rooting-for-the-visitors record.
    var homeAwaySplits: [RecordSplit] {
        var home = (w: 0, l: 0), away = (w: 0, l: 0)
        for g in rootedGames {
            guard let rootedForHome = g.userRootedForHome else { continue }
            if rootedForHome {
                if g.userWon { home.w += 1 } else { home.l += 1 }
            } else {
                if g.userWon { away.w += 1 } else { away.l += 1 }
            }
        }
        return [
            RecordSplit(label: "Your team at home", wins: home.w, losses: home.l),
            RecordSplit(label: "Your team on the road", wins: away.w, losses: away.l),
        ]
    }

    // MARK: - Milestone teaser (first one is free)

    /// Every milestone the user has witnessed, across all completed games.
    var totalMilestonesWitnessed: Int {
        completedGames.reduce(0) { $0 + $1.milestones.count }
    }

    /// The FIRST milestone the user ever witnessed (chronologically earliest
    /// game that has milestones, first milestone of that game). Free users get
    /// this one in full — everything after is Pro.
    var firstWitnessedMilestone: (game: AttendedGame, milestone: PlayerMilestone)? {
        let chrono = completedGames
            .filter { !$0.milestones.isEmpty }
            .sorted { $0.date < $1.date }
        guard let game = chrono.first, let milestone = game.milestones.first else { return nil }
        return (game, milestone)
    }

    /// Whether a given milestone in a given game is the free one.
    func isFreeMilestone(_ milestone: PlayerMilestone, in game: AttendedGame) -> Bool {
        guard let free = firstWitnessedMilestone else { return false }
        return free.game.id == game.id && free.milestone.id == milestone.id
    }
}
