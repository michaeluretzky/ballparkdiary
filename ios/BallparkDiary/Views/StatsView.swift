import SwiftUI

/// Dashboard of derived statistics: totals, record, ballpark progress and milestones.
struct StatsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(StoreViewModel.self) private var storeKit
    @State private var showPaywall: Bool = false

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

                        // Time at the ballpark
                        TimeWatchedCard()
                            .padding(.horizontal, 16)

                        // Deep numbers
                        DeepNumbersCard()
                            .padding(.horizontal, 16)

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

                        // Ballpark quest (Pro)
                        if storeKit.isPremium {
                            BallparkQuestCard()
                                .padding(.horizontal, 16)
                        } else {
                            LockedBallparkQuestCard(onUnlock: { showPaywall = true })
                                .padding(.horizontal, 16)
                        }

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
            .refreshable { await store.refresh(force: true) }
            .navigationDestination(for: AttendedGame.self) { game in
                GameDetailView(game: game)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: storeKit)
            }
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
                            Text(verbatim: "\(pair.year)")
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
                let winRatio = store.completedGames.isEmpty ? 0 : Double(store.winCount) / Double(store.completedGames.count)
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
    @Environment(StoreViewModel.self) private var storeKit
    @State private var expanded: Bool = false
    @State private var showPaywall: Bool = false
    @State private var selectedAchievement: Achievement?

    /// Layout: show all unlocked first, then locked. Pro-gated locked badges
    /// show a lock icon for free users and are fully visible for Pro users.
    private var allAchievements: [Achievement] { store.achievementList }

    private var visibleCount: Int { expanded ? allAchievements.count : min(12, allAchievements.count) }

    private var unlockedCount: Int { allAchievements.filter(\.unlocked).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Achievements")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(unlockedCount)/\(allAchievements.count)")
                    .font(.stat(13, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Array(allAchievements.prefix(visibleCount))) { a in
                    if a.tier == .pro && !storeKit.isPremium {
                        LockedAchievementMini(a: a, onTap: { showPaywall = true })
                    } else {
                        AchievementMini(a: a) {
                            selectedAchievement = a
                        }
                    }
                }
            }

            if allAchievements.count > 12 {
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Show less" : "See all \(allAchievements.count) badges")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Theme.clay)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .nightCardDeep()
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: storeKit)
        }
        .sheet(item: $selectedAchievement) { achievement in
            AchievementDetailSheet(achievement: achievement, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Compact 3-column achievement badge — just the icon with a subtle glow if unlocked.
private struct AchievementMini: View {
    let a: Achievement
    var onTap: () -> Void = {}
    @State private var shimmer: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
            ZStack {
                if a.unlocked {
                    Circle()
                        .fill(a.tint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Circle()
                        .strokeBorder(a.tint.opacity(shimmer ? 0.55 : 0.3), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                } else {
                    Circle()
                        .fill(Theme.cardElevated)
                        .frame(width: 44, height: 44)
                    Circle()
                        .strokeBorder(Theme.textMuted.opacity(0.2), lineWidth: 1)
                        .frame(width: 44, height: 44)
                }

                Image(systemName: a.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(a.unlocked ? a.tint : Theme.textMuted.opacity(0.45))
            }

            Text(a.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(a.unlocked ? Theme.textPrimary : Theme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(a.unlocked ? Theme.cardElevated : Theme.cardElevated.opacity(0.35))
        )
        .opacity(a.unlocked ? 1.0 : 0.55)
        .onAppear { if a.unlocked { shimmer = true } }
        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: shimmer)
        }
        .buttonStyle(.plain)
    }
}

/// Locked Pro badge — shows a tiny lock indicator that opens the paywall.
private struct LockedAchievementMini: View {
    let a: Achievement
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Theme.cardElevated)
                        .frame(width: 44, height: 44)
                    Circle()
                        .strokeBorder(Theme.textMuted.opacity(0.2), lineWidth: 1)
                        .frame(width: 44, height: 44)

                    Image(systemName: a.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textMuted.opacity(0.45))

                    // Tiny lock badge
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Theme.lights)
                        .padding(3)
                        .background(Circle().fill(Theme.nightDeep.opacity(0.9)))
                        .offset(x: 14, y: 14)
                }

                Text(a.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardElevated.opacity(0.35))
            )
            .opacity(0.55)
        }
        .buttonStyle(.plain)
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
                            Text("\(game.awayTeam.fullName) \(game.awayScore) – \(game.homeScore) \(game.homeTeam.fullName)")
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
                        TeamLogoView(team: charm.team, size: 52)
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
                        TeamLogoView(team: pair.team, size: 52)
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

// MARK: - Locked ballpark quest (pro gate)

private struct LockedBallparkQuestCard: View {
    @Environment(DiaryStore.self) private var store
    let onUnlock: () -> Void

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
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.lights)
            }

            Text("Track your progress toward visiting all 30 MLB ballparks.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)

            Button(action: onUnlock) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Unlock with Pro")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Theme.lights)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.lights.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.lights.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .nightCard()
    }
}

// MARK: - Time watched

private struct TimeWatchedCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("Time at the Ballpark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.totalTimeLabel)
                        .font(.scoreboard(30, weight: .black))
                        .foregroundStyle(Theme.textPrimary)
                    Text("total watched")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(store.seasonsActive)")
                        .font(.scoreboard(22, weight: .black))
                        .foregroundStyle(Theme.lights)
                    Text(store.seasonsActive == 1 ? "season" : "seasons")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            if store.totalMinutesWatched > 0 {
                let avgMin = store.totalMinutesWatched / max(1, store.completedGames.count)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text("~ \(avgMin) min per game")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    if store.baseballAge > 0 {
                        Text("Since \(formattedFirstYear)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .padding(16)
        .nightCardDeep()
    }

    private var formattedFirstYear: String {
        guard let first = store.completedGames.map(\.date).min() else { return "" }
        return String(Calendar.current.component(.year, from: first))
    }
}

// MARK: - Deep numbers

private struct DeepNumbersCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.clay)
                Text("Deeper Numbers")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 0) {
                DeepStatTile(
                    value: milesString,
                    label: "Miles traveled",
                    icon: "arrow.triangle.swap"
                )
                Divider().frame(height: 36).background(Color.white.opacity(0.08))
                DeepStatTile(
                    value: String(format: "%.1f", store.averageRunsPerGame),
                    label: "Avg runs/game",
                    icon: "plus.forwardslash.minus"
                )
                Divider().frame(height: 36).background(Color.white.opacity(0.08))
                DeepStatTile(
                    value: "\(store.oneRunGames)",
                    label: "One-run games",
                    icon: "scissors"
                )
            }

            if let best = store.bestMonth {
                Divider().background(Color.white.opacity(0.08))
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.lights)
                    Text("Best month: \(best.name)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("· \(String(format: "%.0f", best.winPct * 100))% win rate over \(best.games) games")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(16)
        .nightCard()
    }

    private var milesString: String {
        let m = store.milesTraveled
        if m >= 1000 { return String(format: "%.0fK", m / 1000) }
        return String(format: "%.0f", m)
    }
}

private struct DeepStatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Text(value)
                    .font(.scoreboard(20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Achievement detail sheet

private struct AchievementDetailSheet: View {
    let achievement: Achievement
    let store: DiaryStore

    /// Games that contributed to unlocking this achievement — only the games
    /// that actually satisfy this specific badge's requirement, not the whole
    /// diary. Collection/division badges show one game per unique qualifying
    /// park; lifetime-total badges legitimately list every game.
    private var contributingGames: [AttendedGame] {
        let games = store.completedGames.sorted { $0.date < $1.date }
        switch achievement.id {
        // ── Collection ──
        case "first":
            return Array(games.prefix(1))
        case "five_parks", "ten_parks", "twenty_parks", "thirty_parks":
            return uniqueParkGames(games)
        case "coast":
            let east: Set<String> = ["yankee-stadium", "fenway-park", "citi-field", "citizens-bank-park"]
            let west: Set<String> = ["dodger-stadium", "oracle-park", "petco-park", "angel-stadium"]
            return uniqueParkGames(games.filter { east.contains($0.ballparkId) || west.contains($0.ballparkId) })
        // ── Division ──
        case "div_ale": return uniqueParkGames(games.filter { divisionParkIds(DiaryStore.alEast).contains($0.ballparkId) })
        case "div_alc": return uniqueParkGames(games.filter { divisionParkIds(DiaryStore.alCentral).contains($0.ballparkId) })
        case "div_alw": return uniqueParkGames(games.filter { divisionParkIds(DiaryStore.alWest).contains($0.ballparkId) })
        case "div_nle": return uniqueParkGames(games.filter { divisionParkIds(DiaryStore.nlEast).contains($0.ballparkId) })
        case "div_nlc": return uniqueParkGames(games.filter { divisionParkIds(DiaryStore.nlCentral).contains($0.ballparkId) })
        case "div_nlw": return uniqueParkGames(games.filter { divisionParkIds(DiaryStore.nlWest).contains($0.ballparkId) })
        case "league": return uniqueParkGames(games)
        // ── Fan dedication (lifetime totals — every game truly counts) ──
        case "iron_fan", "silver_slugger", "century":
            return games
        case "die_hard":
            let groups = Dictionary(grouping: games) { Calendar.current.component(.year, from: $0.date) }
            if let season = groups.first(where: { $0.value.count >= 10 }) {
                return season.value.sorted { $0.date < $1.date }
            }
            return []
        case "back_to_back":
            return backToBackGames(games)
        case "streak", "streak5":
            return games.filter { qualifies(game: $0) }
        // ── Road / rivalry ──
        case "road_warrior":
            let fav = store.favoriteTeam
            return games.filter {
                ($0.homeTeamId == fav.id && $0.userRootedForHome == false)
                    || ($0.awayTeamId == fav.id && $0.userRootedForHome == true)
            }
        case "international":
            return games.filter { $0.ballparkId == "rogers-centre" }
        case "dome_dweller":
            return uniqueParkGames(games.filter { $0.ballpark.roof != .open })
        default:
            return games.filter { qualifies(game: $0) }
        }
    }

    /// First game at each unique ballpark, in chronological order. Used so
    /// collection badges list one representative game per park, not duplicates.
    private func uniqueParkGames(_ games: [AttendedGame]) -> [AttendedGame] {
        var seen = Set<String>()
        var result: [AttendedGame] = []
        for g in games where !seen.contains(g.ballparkId) {
            seen.insert(g.ballparkId)
            result.append(g)
        }
        return result
    }

    /// Home-park ids for a division — what a division-collection badge needs.
    private func divisionParkIds(_ div: DiaryStore.MLBDivision) -> Set<String> {
        Set(div.teamIds.compactMap { Ballpark.by(teamId: $0)?.id })
    }

    /// Pairs of games attended on consecutive days.
    private func backToBackGames(_ games: [AttendedGame]) -> [AttendedGame] {
        let sorted = games.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return [] }
        var result: [AttendedGame] = []
        for i in 1..<sorted.count {
            let diff = Calendar.current.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 99
            if diff == 1 {
                if result.last?.id != sorted[i - 1].id { result.append(sorted[i - 1]) }
                result.append(sorted[i])
            }
        }
        return result
    }

    /// Whether a specific game satisfies an event-based badge requirement.
    private func qualifies(game g: AttendedGame) -> Bool {
        switch achievement.id {
        // ── Game experience ──
        case "extras":        return g.highlights.contains { Int($0.inning.dropFirst()) ?? 0 >= 10 }
        case "walkoff":       return g.highlights.contains { $0.kind == .walkoff }
        case "blowout":       return abs(g.homeScore - g.awayScore) >= 10
        case "duel":          return g.totalRuns <= 2
        case "shutout":       return g.homeScore == 0 || g.awayScore == 0
        case "slugfest":      return g.highlights.filter { $0.kind == .homeRun }.count >= 5
        case "sunday":        return Calendar.current.component(.weekday, from: g.date) == 1
        case "rain":          return g.weather == .rain
        // ── Win streaks ──
        case "streak", "streak5": return g.userWon
        // ── Rivalries ──
        case "rivalry_subway":   return ["nyy", "nym"].contains(g.homeTeamId) && ["nyy", "nym"].contains(g.awayTeamId)
        case "rivalry_freeway":  return ["lad", "laa"].contains(g.homeTeamId) && ["lad", "laa"].contains(g.awayTeamId)
        case "rivalry_crosstown": return ["chc", "cws"].contains(g.homeTeamId) && ["chc", "cws"].contains(g.awayTeamId)
        case "rivalry_ohio":     return ["cin", "cle"].contains(g.homeTeamId) && ["cin", "cle"].contains(g.awayTeamId)
        case "rivalry_lonestar": return ["tex", "hou"].contains(g.homeTeamId) && ["tex", "hou"].contains(g.awayTeamId)
        // ── Hidden ──
        default:
            if achievement.id.hasPrefix("hid_") {
                if let parkId = parkForHidden(id: achievement.id) { return g.ballparkId == parkId }
                if achievement.id == "hid_classic_trio" {
                    return ["fenway-park", "wrigley-field", "dodger-stadium"].contains(g.ballparkId)
                }
                if achievement.id == "hid_one_run"   { return abs(g.homeScore - g.awayScore) == 1 }
                if achievement.id == "hid_blowout15" { return abs(g.homeScore - g.awayScore) >= 15 }
                if achievement.id == "hid_marathon"  { return g.highlights.contains { Int($0.inning.dropFirst()) ?? 0 >= 15 } }
                if achievement.id == "hid_grand_slam" { return g.highlights.contains { $0.description.lowercased().contains("grand slam") } }
                return !g.milestones.isEmpty
            }
            return false
        }
    }

    private func parkForHidden(id: String) -> String? {
        let map: [String: String] = [
            "hid_fenway": "fenway-park", "hid_wrigley": "wrigley-field",
            "hid_bronx": "yankee-stadium", "hid_ravine": "dodger-stadium",
            "hid_splash": "oracle-park", "hid_gateway": "busch-stadium",
            "hid_milehigh": "coors-field", "hid_bigA": "angel-stadium",
            "hid_fountain": "kauffman-stadium", "hid_warehouse": "camden-yards",
            "hid_bridge": "pnc-park"
        ]
        return map[id]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Hero badge
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(achievement.tint.opacity(0.14))
                                    .frame(width: 80, height: 80)
                                Circle()
                                    .strokeBorder(achievement.tint.opacity(0.35), lineWidth: 2)
                                    .frame(width: 80, height: 80)
                                Image(systemName: achievement.symbol)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(achievement.tint)
                            }

                            Text(achievement.title)
                                .font(.scoreboard(24, weight: .black))
                                .foregroundStyle(Theme.textPrimary)

                            Text(achievement.detail)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            if achievement.unlocked {
                                Label("Unlocked", systemImage: "checkmark.seal.fill")
                                    .font(.caps(11, weight: .heavy))
                                    .foregroundStyle(Theme.grass)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(Theme.grass.opacity(0.12))
                                    )
                            } else {
                                Label("Locked", systemImage: "lock.fill")
                                    .font(.caps(11, weight: .heavy))
                                    .foregroundStyle(Theme.textMuted)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(Theme.cardElevated)
                                    )
                            }
                        }
                        .padding(.top, 8)

                        // Contributing games
                        if achievement.unlocked && !contributingGames.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("GAMES CONTRIBUTING")
                                    .font(.caps(10, weight: .heavy))
                                    .tracking(2)
                                    .foregroundStyle(Theme.clay)
                                    .padding(.horizontal, 4)

                                ForEach(contributingGames.prefix(10)) { game in
                                    NavigationLink(value: game) {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(game.homeTeam.primary.opacity(0.2))
                                                    .frame(width: 36, height: 36)
                                                Text(game.homeTeam.abbreviation)
                                                    .font(.system(size: 9, weight: .heavy))
                                                    .foregroundStyle(game.homeTeam.primary)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(game.awayTeam.fullName) @ \(game.homeTeam.fullName)")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(Theme.textPrimary)
                                                    .lineLimit(1)
                                                Text(game.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)))
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(Theme.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Theme.textMuted)
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Theme.cardElevated)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                if contributingGames.count > 10 {
                                    Text("+ \(contributingGames.count - 10) more games")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.textMuted)
                                        .padding(.leading, 4)
                                }
                            }
                            .padding(16)
                            .nightCardDeep()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(achievement.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AttendedGame.self) { game in
                GameDetailView(game: game)
            }
        }
    }
}
