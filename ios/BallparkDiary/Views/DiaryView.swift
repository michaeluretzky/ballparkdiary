import SwiftUI

/// Chronological list of attended games rendered as vintage baseball cards.
struct DiaryView: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 18, pinnedViews: []) {
                        DiaryHeader()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        if !store.upcomingGames.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("UPCOMING")
                                    .font(.caps(11, weight: .heavy))
                                    .tracking(3)
                                    .foregroundStyle(Theme.lights)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 6)

                                ForEach(store.upcomingGames) { game in
                                    NavigationLink(value: game) {
                                        GameCard(game: game)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        ForEach(Array(groupedGames.enumerated()), id: \.element.0) { _, group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.0.uppercased())
                                    .font(.caps(11, weight: .heavy))
                                    .tracking(3)
                                    .foregroundStyle(Theme.clay)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 6)

                                ForEach(group.1) { game in
                                    NavigationLink(value: game) {
                                        GameCard(game: game)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Color.clear.frame(height: 40)
                    }
                }
            }
            .navigationTitle("Diary")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
            .navigationDestination(for: AttendedGame.self) { game in
                GameDetailView(game: game)
            }
        }
    }

    /// Groups completed games by season-year, latest first. Upcoming games are
    /// shown separately at the top of the list.
    private var groupedGames: [(String, [AttendedGame])] {
        let groups = Dictionary(grouping: store.completedGames) { g -> Int in
            Calendar.current.component(.year, from: g.date)
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { ("\($0.key) Season", $0.value.sorted { $0.date > $1.date }) }
    }
}

// MARK: - Header

private struct DiaryHeader: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            HeaderStat(value: "\(store.totalGames)", label: "Games")
            Divider().frame(height: 32).overlay(Color.white.opacity(0.08))
            HeaderStat(value: "\(store.ballparkCount)/30", label: "Parks")
            Divider().frame(height: 32).overlay(Color.white.opacity(0.08))
            HeaderStat(value: "\(store.winCount)-\(store.lossCount)", label: "Record")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .nightCard()
    }
}

private struct HeaderStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.stat(20, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.textMuted)
        }
    }
}

// MARK: - Game card (B+C redesign — ballpark aerial hero, smaller scores)

struct GameCard: View {
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 0) {
            // Ballpark aerial hero
            heroSection

            // Card body
            VStack(spacing: 0) {
                // Date + score bar
                HStack(alignment: .center, spacing: 0) {
                    dateBadge
                    Spacer()
                    scoreBlock
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Team matchup
                HStack(spacing: 6) {
                    TeamChip(team: game.awayTeam, primary: false)
                    Text("@")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.textMuted)
                    TeamChip(team: game.homeTeam, primary: true)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Venue + confirmation row
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.clay)
                    Text(game.ballpark.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if let conf = game.confirmationNumber {
                        Text("#\(conf)")
                            .font(.caps(9, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(Theme.lights.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Theme.lights.opacity(0.12))
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Theme.card)
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }

    // MARK: - Hero section

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            BallparkSnapshot(ballpark: game.ballpark)
                .frame(height: 140)
                .clipped()

            // Gradient fade at bottom for text legibility
            LinearGradient(
                colors: [.clear, Theme.card.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 60)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // Weather badge top-right
            if game.firstPitchTempF > 0 || game.weather != .clear {
                HStack(spacing: 4) {
                    Image(systemName: game.weather.symbol)
                        .font(.system(size: 10, weight: .bold))
                    Text("\(game.firstPitchTempF)°")
                        .font(.stat(10, weight: .heavy))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(.capsule)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    // MARK: - Date badge

    private var dateBadge: some View {
        HStack(spacing: 8) {
            Text(game.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.caps(10, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.clay)
            Text(game.date.formatted(.dateTime.day()))
                .font(.stat(20, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text("'\(String(Calendar.current.component(.year, from: game.date)).suffix(2))")
                .font(.stat(11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Score block (compact)

    private var scoreBlock: some View {
        Group {
            if game.isUpcoming {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.lights)
                    Text(game.date.formatted(.dateTime.hour().minute()))
                        .font(.stat(14, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.lights.opacity(0.10))
                )
            } else {
                HStack(spacing: 8) {
                    Text(game.userWon ? "W" : "L")
                        .font(.scoreboard(13, weight: .black))
                        .foregroundStyle(game.userWon ? Theme.grass : Theme.foul)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill((game.userWon ? Theme.grass : Theme.foul).opacity(0.15))
                        )
                    Text(game.scoreString)
                        .font(.stat(14, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.cardElevated)
                )
            }
        }
    }
}

private struct TeamChip: View {
    let team: Team
    let primary: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(team.primary)
                .overlay(Circle().strokeBorder(team.secondary.opacity(0.7), lineWidth: 1))
                .frame(width: 14, height: 14)
            Text(team.abbreviation)
                .font(.stat(12, weight: .heavy))
                .foregroundStyle(primary ? Theme.textPrimary : Theme.textSecondary)
        }
    }
}
