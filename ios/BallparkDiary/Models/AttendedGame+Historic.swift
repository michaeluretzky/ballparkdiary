import Foundation

/// "Was I at a famous game?" — detects when a diary entry later reads as
/// historic: no-hitters, perfect games, cycles, exact career milestones,
/// walk-offs, extra-inning marathons, and historic blowouts. All derived from
/// verified box-score data already merged into the game.
extension AttendedGame {

    /// Short human label for why this game is historic, or nil when it isn't.
    /// Ordered by rarity so the most impressive reason wins.
    var historicNote: String? {
        guard !isUpcoming else { return nil }

        // Perfect game > no-hitter (from verified milestones).
        if milestones.contains(where: { $0.category == .noHitter && $0.title == "Perfect Game" }) {
            return "A perfect game — one of the rarest feats in baseball"
        }
        if milestones.contains(where: { $0.category == .noHitter }) {
            return "You witnessed a no-hitter"
        }
        if milestones.contains(where: { $0.category == .cycle }) {
            return "A player hit for the cycle"
        }

        // Exact career milestones ("500th Career Home Run") — the chasing
        // variants ("Career HR #497 — Chasing 500") contain an em dash.
        if let career = milestones.first(where: { $0.title.contains("Career") && !$0.title.contains("\u{2014}") }) {
            return "You saw \(career.playerName)'s \(career.title.lowercased())"
        }

        // A Maddux — complete-game shutout on under 100 pitches. Rarer than a
        // 4-hit game and absolutely worth the flag.
        if let maddux = milestones.first(where: { $0.title.contains("Maddux") }) {
            return "\(maddux.playerName) threw a Maddux — a shutout on under 100 pitches"
        }

        // Any complete-game shutout — nine innings, one arm, zero runs.
        if let shutout = milestones.first(where: { $0.title.contains("Complete-Game Shutout") }) {
            return "\(shutout.playerName) threw a complete-game shutout"
        }

        // Hand-curated famous games (managerial milestones, iconic nights) that
        // box-score data alone can't detect.
        if let curated = curatedFamousNote {
            return curated
        }

        // Walk-off finish.
        if highlights.contains(where: { $0.kind == .walkoff }) {
            return "Decided by a walk-off"
        }

        // 15+ inning marathon.
        let marathon = highlights.contains { h in
            if let inning = Int(h.inning.dropFirst()), inning >= 15 { return true }
            return false
        }
        if marathon { return "A 15+ inning marathon" }

        // Historic blowout.
        if abs(homeScore - awayScore) >= 15 {
            return "A historic \(abs(homeScore - awayScore))-run blowout"
        }

        return nil
    }

    /// Whether this game qualifies as a famous/historic game.
    var isHistoric: Bool { historicNote != nil }

    // MARK: - Curated famous games

    /// Famous games that can't be derived from the box score alone — managerial
    /// milestones, iconic franchise nights. Keyed by "yyyy-MM-dd|homeTeamId"
    /// using the league's Eastern-time calendar day.
    private static let curatedFamousGames: [String: String] = [
        // WSH 1 @ STL 2, Busch Stadium — Mike Matheny's 500th career win as a
        // manager (2nd-fastest to 500 in Cardinals history, behind Southworth).
        "2017-07-01|stl": "Mike Matheny's 500th career win as a manager — Cardinals 2, Nationals 1",
    ]

    /// Eastern-time day formatter matching how MLB schedules are keyed.
    private static let easternDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Curated note for this game, if its date + home team match the registry.
    /// Checks both the Eastern-time day and the device's local day so manual
    /// entries (saved at local noon/midnight) still match.
    private var curatedFamousNote: String? {
        let easternKey = "\(Self.easternDayFormatter.string(from: date))|\(homeTeamId)"
        if let note = Self.curatedFamousGames[easternKey] { return note }

        let localFormatter = DateFormatter()
        localFormatter.calendar = Calendar.current
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = TimeZone.current
        localFormatter.dateFormat = "yyyy-MM-dd"
        let localKey = "\(localFormatter.string(from: date))|\(homeTeamId)"
        return Self.curatedFamousGames[localKey]
    }
}
