import SwiftUI

/// Dashboard of derived statistics: totals, record, ballpark progress and milestones.
struct StatsView: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Hero
                        HeroSummary()
                            .padding(.horizontal, 16)

                        // On this day
                        if !store.onThisDayGames.isEmpty {
                            OnThisDayCard()
                                .padding(.horizontal, 16)
                        }

                        // Record / win pct
                        RecordCard()
                            .padding(.horizontal, 16)

                        // Lucky charm
                        LuckyCharmCard()
                            .padding(.horizontal, 16)

                        // Ballparks unlocked
                        BallparkProgressCard()
                            .padding(.horizontal, 16)

                        // 30-ballpark quest
                        BallparkQuestCard()
                            .padding(.horizontal, 16)

                        // Milestones
                        MilestonesCard()
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
        }
    }
}

// MARK: - Hero

private struct HeroSummary: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Career Total".uppercased())
                        .font(.caps(10, weight: .heavy))
                        .tracking(2.5)
                        .foregroundStyle(Theme.clay)
                    Text("\(store.totalGames) games")
                        .font(.scoreboard(34, weight: .black))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                BaseballMark(size: 56)
                    .shadow(color: Theme.clay.opacity(0.4), radius: 10)
            }

            HStack(spacing: 12) {
                StatTile(value: "\(store.ballparkCount)", suffix: "/30", label: "Ballparks")
                StatTile(value: "\(store.totalRuns)", label: "Runs witnessed")
                StatTile(value: "\(store.homeRunsWitnessed)", label: "Home runs")
            }
        }
        .padding(16)
        .nightCard()
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
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.2)
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
            HStack {
                Text("Your Record".uppercased())
                    .font(.caps(11, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.clay)
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
                    Text("WINS")
                        .font(.caps(10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Theme.textMuted)
                }
                Text("–")
                    .font(.scoreboard(28, weight: .black))
                    .foregroundStyle(Theme.textMuted)
                VStack(alignment: .leading) {
                    Text("\(store.lossCount)")
                        .font(.scoreboard(44, weight: .black))
                        .foregroundStyle(Theme.foul)
                    Text("LOSSES")
                        .font(.caps(10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(store.longestStreak)")
                        .font(.scoreboard(28, weight: .black))
                        .foregroundStyle(Theme.lights)
                    Text("BEST STREAK")
                        .font(.caps(9, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            // Win bar
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

// MARK: - Ballpark progress

private struct BallparkProgressCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ballparks Unlocked".uppercased())
                    .font(.caps(11, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.clay)
                Spacer()
                Text("\(store.ballparkCount)/30")
                    .font(.stat(13, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
            }

            // Grid of all 30 parks
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(Ballpark.all) { park in
                    let visited = store.visitedBallparkIds.contains(park.id)
                    Circle()
                        .fill(visited ? AnyShapeStyle(Theme.clayGradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                        .overlay(
                            Circle().strokeBorder(visited ? Theme.lights.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: visited ? "checkmark" : "")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                        )
                }
            }
        }
        .padding(16)
        .nightCard()
    }
}

// MARK: - Milestones

private struct MilestonesCard: View {
    @Environment(DiaryStore.self) private var store

    var milestones: [(symbol: String, title: String, detail: String, unlocked: Bool, color: Color)] {
        [
            ("ticket.fill", "First Game", "Welcome to the diary", store.totalGames >= 1, Theme.clay),
            ("baseball.fill", "Five Stadiums", "Visit 5 unique ballparks", store.ballparkCount >= 5, Theme.lights),
            ("globe.americas.fill", "Coast to Coast", "AL East + NL West parks", coastToCoast, Theme.grass),
            ("star.circle.fill", "Walk-Off Witness", "See a game decided in the final at-bat", witnessedWalkoff, Theme.foul),
            ("flame.fill", "Win Streak x3", "3 wins in a row at games you attended", store.longestStreak >= 3, Theme.clayDeep),
            ("crown.fill", "Pilgrim", "Visit all 30 ballparks", store.ballparkCount == 30, Theme.lights)
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
            Text("Milestones".uppercased())
                .font(.caps(11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.clay)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(milestones.indices, id: \.self) { i in
                    let m = milestones[i]
                    HStack(spacing: 10) {
                        Image(systemName: m.symbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(m.unlocked ? m.color : Theme.textMuted)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill((m.unlocked ? m.color : Theme.textMuted).opacity(0.16))
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(m.unlocked ? Theme.textPrimary : Theme.textMuted)
                                .lineLimit(1)
                            Text(m.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.cardElevated.opacity(m.unlocked ? 1.0 : 0.6))
                    )
                    .opacity(m.unlocked ? 1.0 : 0.7)
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
                Text("On This Day".uppercased())
                    .font(.caps(11, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.clay)
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
        .nightCard()
        .navigationDestination(for: AttendedGame.self) { GameDetailView(game: $0) }
    }

    private func yearsAgo(_ date: Date) -> Int {
        max(1, Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 1)
    }
    private func yearsAgoLabel(_ date: Date) -> String {
        let y = Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
        return y <= 0 ? "earlier this year" : (y == 1 ? "1 year ago today" : "\(y) years ago today")
    }
}

// MARK: - Lucky charm

private struct LuckyCharmCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lucky Charm".uppercased())
                .font(.caps(11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.clay)

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
                Text("Attend a game with your favorite team to unlock your lucky-charm record.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .nightCard()
    }

    private func charmBlurb(_ charm: (wins: Int, losses: Int, team: Team)) -> String {
        let total = charm.wins + charm.losses
        let pct = total > 0 ? Int(Double(charm.wins) / Double(total) * 100) : 0
        if pct >= 60 { return "They win \(pct)% of the time when you're in the stands. Keep showing up." }
        if pct >= 40 { return "A true coin flip with you watching — \(pct)% wins." }
        return "Tough luck so far — \(pct)% wins when you attend."
    }
}

// MARK: - 30 ballpark quest

private struct BallparkQuestCard: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("The 30-Ballpark Quest".uppercased())
                    .font(.caps(11, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.clay)
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
                    Text("Quest complete — all 30 ballparks visited. You're a Pilgrim.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                Text("\(store.ballparksRemaining.count) to go. Next up:")
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
            Text("Most-Seen Opponent".uppercased())
                .font(.caps(11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.clay)

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
                        Text("\(pair.count) games against your favorite team")
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
        .nightCard()
    }
}
