import SwiftUI

/// Ticket options for one specific upcoming game. Every link is scoped as
/// tightly as each site allows:
/// - MLB Box Office: per-game deep link straight from the MLB schedule feed.
/// - Gametime: exact event resolved live (matchup + date verified) with the
///   current lowest all-in price; falls back to a matchup search.
/// - SeatGeek / StubHub: the home team's schedule page (chronological).
/// - Vivid Seats: matchup search (their search doesn't parse dates reliably,
///   so we never bake the date into query text).
///
/// These are outbound links to buy tickets for a real-world event — allowed
/// outside IAP under App Store guideline 3.1.3(f).
struct TicketOptionsSheet: View {
    let game: MLBUpcomingGame
    let park: Ballpark
    let opponent: Team?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var gametime: ResolvedTicketListing?
    @State private var isResolvingGametime: Bool = true

    /// URL-friendly team slug, e.g. "St. Louis Cardinals" → "st-louis-cardinals".
    private var teamSlug: String {
        park.team.fullName
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }

    /// "Chicago Cubs at St. Louis Cardinals" — matchup only, no date text.
    /// Marketplace search engines match team tokens well but parse date
    /// strings poorly, which is how wrong events used to surface.
    private var matchupQuery: String {
        guard let opponent else { return park.team.fullName }
        return "\(opponent.fullName) at \(park.team.fullName)"
    }

    private var dateText: String {
        game.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func searchURL(base: String, param: String, query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: param, value: query)]
        return components?.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Game header ──
            HStack(spacing: 12) {
                if let opponent {
                    TeamLogoView(team: opponent, size: 34, showGloss: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(opponent?.fullName ?? "TBD") at \(park.team.fullName)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text("\(dateText) · \(game.date.formatted(date: .omitted, time: .shortened)) · \(park.name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 8) {
                    // 1. Official box office — always the exact game
                    if let official = game.officialTicketURL {
                        TicketSiteRow(
                            name: "MLB Box Office",
                            detail: "Official · this exact game",
                            symbol: "checkmark.seal.fill",
                            accent: Theme.lights,
                            exact: true
                        ) { openURL(official) }
                    }

                    // 2. Gametime — exact event verified live, with price
                    if isResolvingGametime {
                        TicketSiteRow(
                            name: "Gametime",
                            detail: "Finding this game…",
                            symbol: "hourglass",
                            accent: Theme.textMuted,
                            exact: false,
                            isLoading: true,
                            action: nil
                        )
                    } else if let gametime {
                        TicketSiteRow(
                            name: "Gametime",
                            detail: gametime.fromPriceText.map { "This exact game · \($0) with fees" } ?? "This exact game",
                            symbol: "checkmark.seal.fill",
                            accent: Theme.lights,
                            exact: true
                        ) { openURL(gametime.url) }
                    } else if let fallback = searchURL(base: "https://gametime.co/search", param: "query", query: matchupQuery) {
                        TicketSiteRow(
                            name: "Gametime",
                            detail: "Search this matchup — pick \(game.date.formatted(.dateTime.month(.abbreviated).day()))",
                            symbol: "magnifyingglass",
                            accent: Theme.clay,
                            exact: false
                        ) { openURL(fallback) }
                    }

                    // 3–4. Team schedule pages (chronological — scoped to the right team)
                    if let seatgeek = URL(string: "https://seatgeek.com/\(teamSlug)-tickets") {
                        TicketSiteRow(
                            name: "SeatGeek",
                            detail: "\(park.team.name) schedule — pick \(game.date.formatted(.dateTime.month(.abbreviated).day()))",
                            symbol: "calendar",
                            accent: Theme.clay,
                            exact: false
                        ) { openURL(seatgeek) }
                    }
                    if let stubhub = URL(string: "https://www.stubhub.com/\(teamSlug)-tickets") {
                        TicketSiteRow(
                            name: "StubHub",
                            detail: "\(park.team.name) schedule — pick \(game.date.formatted(.dateTime.month(.abbreviated).day()))",
                            symbol: "calendar",
                            accent: Theme.clay,
                            exact: false
                        ) { openURL(stubhub) }
                    }

                    // 5. Vivid Seats — matchup search
                    if let vivid = searchURL(base: "https://www.vividseats.com/search", param: "searchTerm", query: matchupQuery) {
                        TicketSiteRow(
                            name: "Vivid Seats",
                            detail: "Search this matchup — pick \(game.date.formatted(.dateTime.month(.abbreviated).day()))",
                            symbol: "magnifyingglass",
                            accent: Theme.clay,
                            exact: false
                        ) { openURL(vivid) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                Text("Prices change in real time and vary by site. Ballpark Diary is not affiliated with MLB or any ticket seller and earns nothing from these links.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .presentationContentInteraction(.scrolls)
        .task {
            isResolvingGametime = true
            if let opponent {
                gametime = await TicketFinderService.shared.gametimeListing(
                    home: park.team,
                    away: opponent,
                    gameDate: game.date
                )
            }
            isResolvingGametime = false
        }
    }
}

/// One tappable ticket destination row.
private struct TicketSiteRow: View {
    let name: String
    let detail: String
    let symbol: String
    let accent: Color
    let exact: Bool
    var isLoading: Bool = false
    let action: (() -> Void)?

    init(
        name: String,
        detail: String,
        symbol: String,
        accent: Color,
        exact: Bool,
        isLoading: Bool = false,
        action: (() -> Void)?
    ) {
        self.name = name
        self.detail = detail
        self.symbol = symbol
        self.accent = accent
        self.exact = exact
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 36, height: 36)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.textMuted)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accent)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        if exact {
                            Text("EXACT GAME")
                                .font(.caps(8, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(Theme.night)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.lights))
                        }
                    }
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if !isLoading {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardElevated.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name). \(detail)")
    }
}
