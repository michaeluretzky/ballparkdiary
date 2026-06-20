import SwiftUI

/// Dashboard of derived statistics: totals, record, ballpark progress and milestones.
struct StatsView: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                Theme.nightVignette.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Hero
                        HeroSummary()
                            .padding(.horizontal, 16)

                        // Season heatmap strip
                        if !store.completedGames.isEmpty {
                            SeasonHeatmap()
                                .padding(.horizontal, 16)
                        }

                        // Record / win pct
                        RecordCard()
                            .padding(.horizontal, 16)

                        // Lucky charm
                        LuckyCharmCard()
                            .padding(.horizontal, 16)

                        // Ballpark progress
                        BallparkProgressCard()
                            .padding(.horizontal, 16)

                        // Achievements
                        AchievementsPanel()
                            .padding(.horizontal, 16)

                        // On this day
                        if !store.onThisDayGames.isEmpty {
                            OnThisDayCard()
                                .padding(.horizontal, 16)
                        }

                        // Ballpark quest
                        BallparkQuestCard()
                            .padding(.horizontal, 16)

                        // Top opponents
                        TopOpponentCard()
                            .padding(.horizontal, 16)

                        Color.clear.frame(height: 30)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
        }
    }
}

// MARK: - Hero

private struct HeroSummary: View {
    @Environment(DiaryStore.self) private var store
    private var tc: TeamColors { .from(team: store.favoriteTeam) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lifetime")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tc.primary)
                    Text("\(store.totalGames) games")
                        .font(.scoreboard(34, weight: .black))
                        .foregroundStyle(Theme.textPrimary)
                    Text("since day one")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                BaseballMark(size: 56)
                    .shadow(color: tc.primary.opacity(0.4), radius: 10)
            }

            HStack(spacing: 12) {
                StatTile(value: "\(store.ballparkCount)", suffix: "/30", label: "Ballparks")
                StatTile(value: "\(store.totalRuns)", label: "Runs")
                StatTile(value: "\(store.homeRunsWitnessed)", label: "Home runs")
            }
        }
        .padding(16)
        .nightCard()
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(tc.primary)
                .frame(width: 36, height: 3)
                .clipShape(.capsule)
                .offset(y: -1.5)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - Season heatmap

private struct SeasonHeatmap: View {
    @Environment(DiaryStore.self) private var store

    private var yearlyData: [(year: Int, count: Int)] {
        let groups = Dictionary(grouping: store.completedGames) { g in
            Calendar.current.component(.year, from: g.date)
        }
        return groups.map { ($0.key, $0.value.count) }.sorted { $0.year < $1.year }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Season by season")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            if yearlyData.isEmpty {
                Text("Attend a game to start building your history.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            } else {
                let maxCount = yearlyData.map(\.count).max() ?? 1
                VStack(spacing: 6) {
                    ForEach(yearlyData, id: \.year) { pair in
                        HStack(spacing: 10) {
                            Text("\(pair.year)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                                .frame(width: 42, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Theme.cardElevated)
                                        .frame(height: 14)

                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Theme.clay, Theme.lights],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(8, geo.size.width * CGFloat(pair.count) / CGFloat(maxCount)), height: 14)
                                }
                            }
                            .frame(height: 14)

                            Text("\(pair.count)")
                                .font(.stat(12, weight: .heavy))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 20, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(16)
        .nightCardDeep()
    }
}

private struct StatTile: View {
    let value: String
    var suffix: String = ""
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.stat(24, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.stat(13, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardElevated)
        )
    }
}

// MARK: - Record

private struct RecordCard: View {
    @Environment(DiaryStore.self) private var store
    @State private var animateBar: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("W–L")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(percentString)
                    .font(.stat(13, weight: .heavy))
                    .foregroundStyle(Theme.lights)
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading) {
                    Text("\(store.winCount)")
                        .font(.scoreboard(44, weight: .black))
                        .foregroundStyle(Theme.grass)
                    Text("W")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                Text("–")
                    .font(.scoreboard(28, weight: .black))
                    .foregroundStyle(Theme.textMuted)
                VStack(alignment: .leading) {
                    Text("\(store.lossCount)")
                        .font(.scoreboard(44, weight: .black))
                        .foregroundStyle(Theme.foul)
                    Text("L")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(store.longestStreak)")
                        .font(.scoreboard(28, weight: .black))
                        .foregroundStyle(Theme.lights)
                    Text("Best streak")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let winRatio = store.games.isEmpty ? 0 : Double(store.winCount) / Double(store.games.count)
                let winWidth = totalWidth * (animateBar ? winRatio : 0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.foul.opacity(0.85))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.grass, Theme.grass.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: winWidth)
                }
            }
            .frame(height: 8)
            .onAppear {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) {
                    animateBar = true
                }
            }
        }
        .padding(16)
        .nightCard()
    }

    private var percentString: String {
        let p = store.winPct * 100
        return String(format: "%.0f%% win rate", p)
    }
}

// MARK: - Achievements panel (medallions)

private struct AchievementsPanel: View {
    @Environment(DiaryStore.self) private var store

    private var achievements: [(id: String, symbol: String, title: String, detail: String, unlocked: Bool, tint: Color)] {
        [
            ("first", "ticket.fill", "First Game", "Welcome to the diary", store.totalGames >= 1, Theme.clay),
            ("five", "building.columns.fill", "Five Stadiums", "Visit 5 unique ballparks", store.ballparkCount >= 5, Theme.lights),
            ("coast", "globe.americas.fill", "Coast to Coast", "AL East + NL West", coastToCoast, Theme.grass),
            ("walkoff", "star.circle.fill", "Walk-Off", "A game decided in the final at-bat", witnessedWalkoff, Theme.foul),
            ("streak", "flame.fill", "Win Streak x3", "3 wins in a row", store.longestStreak >= 3, Theme.clayDeep),
            ("pilgrim", "crown.fill", "Pilgrim", "All 30 ballparks visited", store.ballparkCount == 30, Theme.lights)
        ]
    }

    private var witnessedWalkoff: Bool {
        store.games.flatMap(\.highlights).contains(where: { $0.kind == .walkoff })
    }
    private var coastToCoast: Bool {
        let east = store.visitedBallparkIds.intersection(["yankee-stadium", "fenway-park", "citi-field", "citizens-bank-park"])
        let west = store.visitedBallparkIds.intersection(["dodger-stadium", "oracle-park", "petco-park", "angel-stadium"])
        return !east.isEmpty && !west.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(achievements, id: \.id) { a in
                    AchievementPendant(
                        symbol: a.symbol,
                        title: a.title,
                        detail: a.detail,
                        unlocked: a.unlocked,
                        tint: a.tint
                    )
                }
            }
        }
        .padding(16)
        .nightCardDeep()
    }
}

/// Custom achievement badge — a hexagonal pendant / patch instead of SF Symbol
/// in a tinted circle. Unlocked = full color with glow; locked = desaturated.
private struct AchievementPendant: View {
    let symbol: String
    let title: String
    let detail: String
    let unlocked: Bool
    let tint: Color
    @State private var shimmer: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Hex badge
            ZStack {
                if unlocked {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Circle()
                        .strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 42, height: 42)
                    // Glow ring
                    Circle()
                        .strokeBorder(tint.opacity(shimmer ? 0.6 : 0.2), lineWidth: 2)
                        .frame(width: 48, height: 48)
                        .blur(radius: 3)
                } else {
                    Circle()
                        .fill(Theme.cardElevated)
                        .frame(width: 42, height: 42)
                    Circle()
                        .strokeBorder(Theme.textMuted.opacity(0.3), lineWidth: 1)
                        .frame(width: 42, height: 42)
                }

                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(unlocked ? tint : Theme.textMuted)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textMuted)
                    .lineLimit(1)
                Text(unlocked ? detail : "Not yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardElevated.opacity(unlocked ? 1.0 : 0.5))
        )
        .opacity(unlocked ? 1.0 : 0.65)
        .onAppear {
            if unlocked { shimmer = true }
        }
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: shimmer)
    }
}

// MARK: - Ballpark progress

private struct BallparkProgressCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ballparks visited")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(store.ballparkCount)/30")
                    .font(.stat(13, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10), spacing: 5) {
                ForEach(Ballpark.all) { park in
                    let visited = store.visitedBallparkIds.contains(park.id)
                    Circle()
                        .fill(visited ? AnyShapeStyle(
                            LinearGradient(colors: [park.team.primary, park.team.primary.opacity(0.7)],
                                           startPoint: .top, endPoint: .bottom)
                        ) : AnyShapeStyle(Color.white.opacity(0.06)))
                        .overlay(
                            Circle().strokeBorder(visited ? park.team.secondary.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Group {
                                if visited {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                        )
                }
            }
        }
        .padding(16)
        .nightCard()
    }
}

// MARK: - On this day

private struct OnThisDayCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("On this day")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }

            ForEach(store.onThisDayGames) { game in
                NavigationLink(value: game) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(game.winnerTeam.primary)
                            Text("\(yearsAgo(game.date))")
                                .font(.stat(15, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(game.awayTeam.abbreviation) \(game.awayScore) – \(game.homeScore) \(game.homeTeam.abbreviation)")
                                .font(.scoreboard(15, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(game.ballpark.name) · \(yearsAgoLabel(game.date))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardElevated))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .nightCardDeep()
        .navigationDestination(for: AttendedGame.self) { GameDetailView(game: $0) }
    }

    private func yearsAgo(_ date: Date) -> Int {
        max(1, Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 1)
    }
    private func yearsAgoLabel(_ date: Date) -> String {
        let y = Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
        return y <= 0 ? "This year" : (y == 1 ? "1 year ago" : "\(y) years ago")
    }
}

// MARK: - Lucky charm

private struct LuckyCharmCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lucky charm")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            if let charm = store.luckyCharm, charm.wins + charm.losses > 0 {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(charm.team.primary)
                        Circle().strokeBorder(charm.team.secondary, lineWidth: 2)
                        Text(charm.team.abbreviation)
                            .font(.stat(14, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(charm.team.fullName) are \(charm.wins)–\(charm.losses)")
                            .font(.scoreboard(17, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(charmBlurb(charm))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("See your favorite team live to unlock your lucky-charm record.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .nightCardDeep()
    }

    private func charmBlurb(_ charm: (wins: Int, losses: Int, team: Team)) -> String {
        let total = charm.wins + charm.losses
        let pct = total > 0 ? Int(Double(charm.wins) / Double(total) * 100) : 0
        if pct >= 65 { return "\(pct)% win rate when you're in the building." }
        if pct >= 45 { return "\(pct)% wins — coin flip when you show up." }
        return "\(pct)% wins. The baseball gods owe you."
    }
}

// MARK: - 30 ballpark quest

private struct BallparkQuestCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("The 30-ballpark quest")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(store.ballparkCount)/30")
                    .font(.stat(13, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
            }

            if store.ballparksRemaining.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.lights)
                    Text("Every park, every city. You've done it.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                Text("\(store.ballparksRemaining.count) left. Next up:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                VStack(spacing: 8) {
                    ForEach(store.ballparksRemaining.prefix(3)) { park in
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(park.team.primary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(park.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("\(park.city), \(park.state)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardElevated))
                    }
                }
            }
        }
        .padding(16)
        .nightCard()
    }
}

// MARK: - Top opponent

private struct TopOpponentCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most-seen opponent")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            if let pair = store.mostSeenOpponent {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(pair.team.primary)
                        Circle().strokeBorder(pair.team.secondary, lineWidth: 2)
                        Text(pair.team.abbreviation)
                            .font(.stat(13, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pair.team.fullName)
                            .font(.scoreboard(18, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(pair.count) games against your team")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
            } else {
                Text("Not enough games yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            }

            if let home = store.homeBallpark {
                Divider().background(Color.white.opacity(0.08))
                HStack(spacing: 14) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.lights)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Theme.lights.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(home.name)
                            .font(.scoreboard(18, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Your home ballpark")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .nightCardDeep()
    }
}
