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
            .navigationDestination(for: AttendedGame.self) { game in
                GameDetailView(game: game)
            }
        }
    }

    /// Groups games by season-year, latest first.
    private var groupedGames: [(String, [AttendedGame])] {
        let groups = Dictionary(grouping: store.games) { g -> Int in
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

// MARK: - Game card (vintage baseball card)

struct GameCard: View {
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 0) {
            // Color strip (team colors, gradient)
            LinearGradient(
                colors: [game.awayTeam.primary, game.homeTeam.primary],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            HStack(spacing: 14) {
                // Date stamp
                VStack(spacing: 0) {
                    Text(game.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.caps(10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.clay)
                    Text(game.date.formatted(.dateTime.day()))
                        .font(.scoreboard(28, weight: .black))
                        .foregroundStyle(Theme.textPrimary)
                    Text(String(Calendar.current.component(.year, from: game.date)))
                        .font(.stat(10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(width: 60)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.cardElevated)
                )

                // Matchup + meta
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        TeamChip(team: game.awayTeam, primary: false)
                        Text("@")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.textMuted)
                        TeamChip(team: game.homeTeam, primary: true)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Text(game.ballpark.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 10) {
                        Label(game.weather.rawValue, systemImage: game.weather.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .labelStyle(.titleAndIcon)
                        Text("·").foregroundStyle(Theme.textMuted)
                        Text("\(game.firstPitchTempF)°F")
                            .font(.stat(11, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Score block
                VStack(alignment: .trailing, spacing: 4) {
                    Text(game.userWon ? "W" : "L")
                        .font(.scoreboard(18, weight: .black))
                        .foregroundStyle(game.userWon ? Theme.grass : Theme.foul)
                        .frame(width: 32, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill((game.userWon ? Theme.grass : Theme.foul).opacity(0.15))
                        )
                    Text(game.scoreString)
                        .font(.stat(18, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Final")
                        .font(.caps(9, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
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
