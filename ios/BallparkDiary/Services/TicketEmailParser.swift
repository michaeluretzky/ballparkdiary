import Foundation

/// A lightweight ticket-text message fed to the parser. Sendable & isolation-
/// free so it can be processed off the main actor. `snippet` carries the full
/// extracted ticket text (OCR / PDF / shared text).
nonisolated struct EmailMessage: Sendable, Hashable {
    let id: String
    let subject: String
    let from: String
    let snippet: String
    let internalDate: Date
}

/// A possible game day pulled from a ticket. Month/day are always present; the
/// year is only set when the ticket spells out a 4-digit year, otherwise it's
/// resolved later by matching the real MLB schedule.
nonisolated struct DateHint: Sendable, Hashable {
    let month: Int
    let day: Int
    let year: Int?
}

/// A candidate attended game detected from a ticket. The team ids are MLB Stats
/// API numeric ids used to confirm the matchup against the real schedule; the
/// date hints narrow down which game. Crucially we never invent a date — if the
/// ticket has no readable date, no game is emitted. Isolation-free so it can run
/// off the main actor.
nonisolated struct DetectedGame: Sendable, Hashable {
    let dateHints: [DateHint]
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

            // Only the date the ticket actually contains — never the share date.
            let hints = extractDateHints(from: haystack)
            guard !hints.isEmpty else { continue }

            detected.append(
                DetectedGame(
                    dateHints: hints,
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

    /// Month abbreviations → month number. Long names match too since we only
    /// look at the first three letters.
    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    /// Pull every plausible game day out of the ticket text. Handles spelled-out
    /// months ("Mon, Aug 22", "August 22, 2022") and numeric dates ("8/22/22",
    /// "08-22-2022"). The year is captured only when explicit — otherwise it's
    /// left nil so the MLB schedule confirmation resolves the correct season.
    static func extractDateHints(from text: String) -> [DateHint] {
        var hints: [DateHint] = []
        var seen = Set<String>()
        func push(month: Int, day: Int, year: Int?) {
            guard (1...12).contains(month), (1...31).contains(day) else { return }
            let normalizedYear: Int?
            if let year { normalizedYear = year < 100 ? 2000 + year : year } else { normalizedYear = nil }
            let key = "\(normalizedYear ?? 0)-\(month)-\(day)"
            if seen.insert(key).inserted {
                hints.append(DateHint(month: month, day: day, year: normalizedYear))
            }
        }

        // Spelled-out month + day (+ optional 4-digit year).
        if let regex = try? NSRegularExpression(
            pattern: "(?i)(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*,?\\s*(\\d{4}))?"
        ) {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let monthWord = ns.substring(with: m.range(at: 1)).lowercased()
                guard let month = monthNumbers[String(monthWord.prefix(3))] else { continue }
                let day = Int(ns.substring(with: m.range(at: 2))) ?? 0
                let year = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : nil
                push(month: month, day: day, year: year)
            }
        }

        // Numeric M/D(/YY|/YYYY) or M-D(-YY|-YYYY).
        if let regex = try? NSRegularExpression(
            pattern: "\\b(\\d{1,2})[/-](\\d{1,2})(?:[/-](\\d{2,4}))?\\b"
        ) {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let month = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let day = Int(ns.substring(with: m.range(at: 2))) ?? 0
                let year = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : nil
                push(month: month, day: day, year: year)
            }
        }

        return hints
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
