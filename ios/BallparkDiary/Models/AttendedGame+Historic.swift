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
}
