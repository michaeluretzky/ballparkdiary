import Foundation

/// A candidate attended game detected from a ticket email. The date is a best
/// guess from the email text (falling back to the received date); the team id
/// is the MLB Stats API numeric id used to confirm the matchup against the
/// real schedule. Isolation-free so it can run off the main actor.
nonisolated struct DetectedGame: Sendable, Hashable {
    let candidateDates: [Date]
    let teamMlbId: Int
    let opponentMlbId: Int?
    let source: String
    let subject: String
}

/// Heuristic parser that scans ticket-receipt emails for an MLB matchup and a
/// likely game date. Intentionally conservative: a game is only emitted when at
/// least one team can be identified, so it can be verified against the real
/// schedule downstream. Pure value logic — no UI / model dependencies.
nonisolated enum TicketEmailParser {

    static func detect(in messages: [EmailMessage]) -> [DetectedGame] {
        var detected: [DetectedGame] = []
        for message in messages {
            let haystack = "\(message.subject) \(message.snippet)"
            let teams = matchedTeams(in: haystack)
            guard let primary = teams.first else { continue }

            var dates = extractDates(from: haystack)
            // Always include the received date as a fallback candidate.
            dates.append(message.internalDate)
            dates = dedupedByDay(dates)

            detected.append(
                DetectedGame(
                    candidateDates: dates,
                    teamMlbId: primary,
                    opponentMlbId: teams.dropFirst().first,
                    source: source(from: message.from, subject: message.subject),
                    subject: message.subject.isEmpty ? message.snippet : message.subject
                )
            )
        }
        return detected
    }

    // MARK: - Team detection

    /// Ordered, de-duplicated MLB team ids mentioned in the text.
    private static func matchedTeams(in text: String) -> [Int] {
        let lower = " " + text.lowercased() + " "
        var hits: [(range: Range<String.Index>, id: Int)] = []
        for (keyword, id) in teamKeywords {
            if let range = lower.range(of: " " + keyword + " ") {
                hits.append((range, id))
            } else if let range = lower.range(of: keyword) {
                // Looser match for keywords that may abut punctuation.
                hits.append((range, id))
            }
        }
        let ordered = hits.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var seen = Set<Int>()
        var result: [Int] = []
        for hit in ordered where !seen.contains(hit.id) {
            seen.insert(hit.id)
            result.append(hit.id)
        }
        return result
    }

    // MARK: - Date detection

    private static func extractDates(from text: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        let now = Date()
        return matches.compactMap { $0.date }.filter { $0 <= now.addingTimeInterval(60 * 60 * 24 * 2) }
    }

    private static func dedupedByDay(_ dates: [Date]) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        var seen = Set<DateComponents>()
        var result: [Date] = []
        for date in dates {
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            if !seen.contains(comps) {
                seen.insert(comps)
                result.append(date)
            }
        }
        return result
    }

    // MARK: - Source detection

    private static func source(from sender: String, subject: String) -> String {
        let blob = (sender + " " + subject).lowercased()
        for (needle, label) in sourceLabels where blob.contains(needle) {
            return label
        }
        return "Email receipt"
    }

    private static let sourceLabels: [(String, String)] = [
        ("ticketmaster", "Ticketmaster"), ("seatgeek", "SeatGeek"),
        ("stubhub", "StubHub"), ("axs", "AXS"), ("vividseats", "Vivid Seats"),
        ("vivid seats", "Vivid Seats"), ("gametime", "Gametime"),
        ("tickpick", "TickPick"), ("ballpark", "MLB Ballpark"),
        ("mlb.com", "MLB.com"), ("tickets.com", "Tickets.com")
    ]

    // MARK: - Keyword → MLB Stats API team id

    /// Lowercased keywords mapped to MLB Stats API numeric team ids. Includes
    /// nicknames and host cities so matchups can be picked out of subjects like
    /// "Yankees vs Red Sox" or "Your trip to Wrigley Field".
    private static let teamKeywords: [(String, Int)] = [
        ("diamondbacks", 109), ("d-backs", 109), ("dbacks", 109), ("arizona", 109),
        ("braves", 144), ("atlanta", 144),
        ("orioles", 110), ("baltimore", 110), ("camden", 110),
        ("red sox", 111), ("redsox", 111), ("fenway", 111), ("boston", 111),
        ("cubs", 112), ("wrigley", 112),
        ("white sox", 145), ("whitesox", 145),
        ("reds", 113), ("cincinnati", 113),
        ("guardians", 114), ("cleveland", 114), ("progressive field", 114),
        ("rockies", 115), ("colorado", 115), ("coors", 115),
        ("tigers", 116), ("detroit", 116), ("comerica", 116),
        ("astros", 117), ("houston", 117), ("minute maid", 117), ("daikin park", 117),
        ("royals", 118), ("kansas city", 118), ("kauffman", 118),
        ("angels", 108), ("anaheim", 108),
        ("dodgers", 119), ("chavez ravine", 119),
        ("marlins", 146), ("loandepot", 146),
        ("brewers", 158), ("milwaukee", 158),
        ("twins", 142), ("minnesota", 142), ("target field", 142),
        ("mets", 121), ("citi field", 121),
        ("yankees", 147), ("yankee stadium", 147), ("bronx bombers", 147),
        ("athletics", 133), ("oakland", 133),
        ("phillies", 143), ("philadelphia", 143), ("citizens bank", 143),
        ("pirates", 134), ("pittsburgh", 134), ("pnc park", 134),
        ("padres", 135), ("petco", 135), ("san diego", 135),
        ("giants", 137), ("oracle park", 137), ("san francisco", 137),
        ("mariners", 136), ("seattle", 136), ("t-mobile park", 136),
        ("cardinals", 138), ("st. louis", 138), ("st louis", 138), ("busch stadium", 138),
        ("rays", 139), ("tampa", 139), ("tropicana", 139),
        ("rangers", 140), ("globe life", 140), ("arlington", 140),
        ("blue jays", 141), ("bluejays", 141), ("toronto", 141), ("rogers centre", 141),
        ("nationals", 120), ("washington", 120)
    ]
}
