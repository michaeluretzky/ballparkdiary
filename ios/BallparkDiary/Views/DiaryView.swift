import SwiftUI

/// Chronological list of attended games with ballpark aerial hero photos,
/// compact scores, confirmation numbers, and subtle parallax on scroll.
struct DiaryView: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    if store.games.isEmpty {
                        EmptyDiaryView()
                            .padding(.horizontal, 16)
                            .padding(.top, 40)
                    } else {
                        DiaryHeader()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        if !store.upcomingGames.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(store.favoriteTeam.primary)
                                        .frame(width: 8, height: 8)
                                    Text("ON DECK")
                                        .font(.caps(11, weight: .heavy))
                                        .tracking(3)
                                        .foregroundStyle(store.favoriteTeam.primary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 6)

                                ForEach(store.upcomingGames) { game in
                                    NavigationLink(value: game) {
                                        GameCard(game: game)
                                            .padding(.horizontal, 16)
                                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                                content
                                                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
                                                    .opacity(phase.isIdentity ? 1 : 0.7)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation { store.deleteGame(game.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }

                        ForEach(Array(groupedGames.enumerated()), id: \.element.0) { _, group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Rectangle()
                                        .fill(store.favoriteTeam.primary.opacity(0.6))
                                        .frame(width: 24, height: 2)
                                        .clipShape(.capsule)
                                    Text(group.0)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 6)

                                ForEach(group.1) { game in
                                    NavigationLink(value: game) {
                                        GameCard(game: game)
                                            .padding(.horizontal, 16)
                                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                                content
                                                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
                                                    .opacity(phase.isIdentity ? 1 : 0.7)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation { store.deleteGame(game.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 40)
                }
            }
            .background {
                Theme.nightGradient.ignoresSafeArea()
                Theme.nightVignette.ignoresSafeArea()
            }
            .navigationTitle("Diary")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.nightDeep.opacity(0.95), for: .navigationBar)
            .refreshable {
                let count = await store.refresh(force: true)
                if count > 0 {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                }
            }
            .navigationDestination(for: AttendedGame.self) { game in
                GameDetailView(game: game)
            }
        }
    }

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
    private var tc: TeamColors { .from(team: store.favoriteTeam) }

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
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(tc.primary)
                .frame(width: 40, height: 3)
                .clipShape(.capsule)
                .padding(.horizontal, 16)
                .offset(y: -1.5)
        }
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
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
    }
}

// MARK: - Game card

struct GameCard: View {
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 0) {
            heroSection

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    dateBadge
                    Spacer()
                    scoreBlock
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                HStack(spacing: 6) {
                    TeamChip(team: game.awayTeam, primary: false)
                    Text("@")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.textMuted)
                    TeamChip(team: game.homeTeam, primary: true)
                    Spacer()
                    verifiedDot
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                HStack(spacing: 8) {
                    Image(systemName: "mappin")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TeamColors.from(team: game.homeTeam).primary)
                    Text(game.ballpark.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if let conf = game.confirmationNumber {
                        Text("#\(conf)")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
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
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }

    // MARK: Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            BallparkSnapshot(ballpark: game.ballpark)
                .frame(height: 160)
                .scaleEffect(1.08) // slight overscan for parallax feel
                .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(game.ballpark.name)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 6))
                .padding(10)

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

    // MARK: Date badge

    private var dateBadge: some View {
        HStack(spacing: 8) {
            Text(game.date.formatted(.dateTime.month(.abbreviated)))
                .font(.caps(10, weight: .heavy))
                .tracking(1)
                .foregroundStyle(TeamColors.from(team: game.homeTeam).primary)
            Text(game.date.formatted(.dateTime.day()))
                .font(.stat(20, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(String(Calendar.current.component(.year, from: game.date)))
                .font(.stat(11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: Score block

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

    // MARK: Verified indicator

    @ViewBuilder
    private var verifiedDot: some View {
        if game.verified {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.grass.opacity(0.85))
        } else {
            Image(systemName: "questionmark.diamond")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted.opacity(0.6))
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

// MARK: - Empty diary

private struct EmptyDiaryView: View {
    @Environment(DiaryStore.self) private var store
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 30)

            // Animated baseball illustration
            ZStack {
                Circle()
                    .fill(Theme.lights.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                Circle()
                    .strokeBorder(Theme.lights.opacity(0.15), lineWidth: 1)
                    .frame(width: 180, height: 180)
                    .scaleEffect(pulse ? 1.05 : 0.95)

                BaseballMark(size: 80)
                    .shadow(color: Theme.lights.opacity(0.3), radius: 16)
            }
            .padding(.bottom, 4)

            Text("Your diary is waiting.")
                .font(.scoreboard(24, weight: .black))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Share a ticket screenshot or add a game by hand to begin building your ballpark history.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .lineSpacing(3)

            VStack(spacing: 14) {
                EmptyTip(
                    icon: "square.and.arrow.down.fill",
                    color: Theme.lights,
                    text: "Tap Share on any ticket, then pick Ballpark Diary."
                )
                EmptyTip(
                    icon: "square.and.pencil",
                    color: store.favoriteTeam.primary,
                    text: "Or tap 'Add a Game' in Sources for older stubs."
                )
            }
            .padding(.top, 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct EmptyTip: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(0.14)))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardElevated.opacity(0.6))
        )
    }
}
