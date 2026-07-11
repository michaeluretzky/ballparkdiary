import Foundation

/// A marketplace listing resolved to one specific MLB game (right matchup,
/// right date), including the lowest verified price when the marketplace
/// reports one.
nonisolated struct ResolvedTicketListing: Sendable, Hashable {
    /// Deep link straight to the event's ticket page.
    let url: URL
    /// Lowest all-in price (fees included) in cents, if reported.
    let allInPriceCents: Int?

    /// "from $88" — whole dollars, fees included. Nil when no price reported.
    var fromPriceText: String? {
        guard let cents = allInPriceCents, cents > 0 else { return nil }
        let dollars = (Double(cents) / 100.0).rounded(.up)
        return "from $\(Int(dollars))"
    }
}

/// Resolves ticket-marketplace deep links for a specific MLB game.
///
/// Gametime exposes a public, key-free search endpoint that returns exact
/// events with venue timezones and current lowest prices. We match on the
/// exact matchup name AND the game's calendar day in the ballpark's own
/// timezone, so the link can never point at the wrong game. Any failure
/// returns nil and callers fall back to a plain matchup search page.
nonisolated final class TicketFinderService: Sendable {
    static let shared = TicketFinderService()
    private init() {}

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// Find the exact Gametime event for `away` at `home` on the calendar day
    /// of `gameDate` (evaluated in the venue's local timezone). Doubleheaders
    /// resolve to the game closest in time to the MLB-scheduled first pitch.
    func gametimeListing(home: Team, away: Team, gameDate: Date) async -> ResolvedTicketListing? {
        let matchup = "\(away.fullName) at \(home.fullName)"
        var components = URLComponents(string: "https://mobile.gametime.co/v1/search")!
        components.queryItems = [URLQueryItem(name: "q", value: matchup)]
        guard
            let url = components.url,
            let (data, response) = try? await Self.session.data(from: url),
            let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
            let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return nil }

        var best: (listing: ResolvedTicketListing, distance: TimeInterval)? = nil

        for wrapper in decoded.events ?? [] {
            let event = wrapper.event
            guard
                event.category?.caseInsensitiveCompare("mlb") == .orderedSame,
                let name = event.name,
                name.hasPrefix(matchup),          // exact matchup; tolerates "(Giveaway)" suffixes
                event.dateTBD != true, event.tbd != true,
                let localTime = event.datetimeLocal,
                let tzName = wrapper.venue?.timezone,
                let timeZone = TimeZone(identifier: tzName),
                let eventDate = Self.parseLocal(localTime, in: timeZone)
            else { continue }

            // Same calendar day at the ballpark — never a different game.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            guard calendar.isDate(eventDate, inSameDayAs: gameDate) else { continue }

            guard let eventURL = Self.eventURL(for: event) else { continue }
            let cents = event.minPrice?.total
            let listing = ResolvedTicketListing(
                url: eventURL,
                allInPriceCents: (cents ?? 0) > 0 ? cents : nil
            )
            let distance = abs(eventDate.timeIntervalSince(gameDate))
            if best == nil || distance < (best?.distance ?? .infinity) {
                best = (listing, distance)
            }
        }
        return best?.listing
    }

    /// Parse Gametime's zone-less local timestamp ("2026-08-14T13:20:00")
    /// in the venue's own timezone.
    private static func parseLocal(_ value: String, in timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: value)
    }

    private static func eventURL(for event: SearchEvent) -> URL? {
        if let seo = event.seoURL, let url = URL(string: seo), url.scheme?.hasPrefix("http") == true {
            return url
        }
        guard let id = event.id, !id.isEmpty else { return nil }
        return URL(string: "https://gametime.co/events/\(id)")
    }

    // MARK: - Response shapes (only the fields we read)

    private struct SearchResponse: Codable {
        let events: [EventWrapper]?
    }

    private struct EventWrapper: Codable {
        let event: SearchEvent
        let venue: SearchVenue?
    }

    private struct SearchEvent: Codable {
        let id: String?
        let name: String?
        let category: String?
        let datetimeLocal: String?
        let minPrice: PriceBlock?
        let seoURL: String?
        let tbd: Bool?
        let dateTBD: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name, category, tbd
            case datetimeLocal = "datetime_local"
            case minPrice = "min_price"
            case seoURL = "seo_url"
            case dateTBD = "date_tbd"
        }
    }

    private struct PriceBlock: Codable {
        /// All-in price including fees, in cents.
        let total: Int?
    }

    private struct SearchVenue: Codable {
        let timezone: String?
    }
}
