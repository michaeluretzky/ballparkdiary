import SwiftUI

/// Deep-dive into a player career milestone the user witnessed in person.
/// Linked from `MilestonesPanel` on the game detail screen.
struct MilestoneDetailView: View {
    let milestone: PlayerMilestone
    let game: AttendedGame

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    HeroPanel(milestone: milestone)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    DetailCard(milestone: milestone)
                        .padding(.horizontal, 16)

                    ContextCard(milestone: milestone)
                        .padding(.horizontal, 16)

                    GameContextCard(game: game, milestone: milestone)
                        .padding(.horizontal, 16)

                    SourceLine()
                        .padding(.horizontal, 16)

                    Color.clear.frame(height: 24)
                }
                .padding(.top, 6)
            }
        }
        .navigationTitle("Milestone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.nightDeep, for: .navigationBar)
    }
}

// MARK: - Hero

private struct HeroPanel: View {
    let milestone: PlayerMilestone

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(milestone.team.primary.opacity(0.45))
                    .frame(width: 200, height: 200)
                    .blur(radius: 30)

                ZStack {
                    Circle().fill(Theme.clayGradient)
                    Circle().strokeBorder(Theme.lights, lineWidth: 3)
                    Image(systemName: milestone.category.symbol)
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 124, height: 124)
                .shadow(color: Theme.clay.opacity(0.4), radius: 18, y: 6)
            }
            .frame(height: 200)

            VStack(spacing: 6) {
                Text(milestone.category.label.uppercased())
                    .font(.caps(10, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(Theme.clay)

                Text(milestone.title)
                    .font(.scoreboard(26))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(milestone.team.primary)
                        Circle().strokeBorder(milestone.team.secondary, lineWidth: 1.5)
                        TeamLogoView(team: milestone.team, size: 24, showGloss: false)
                    }
                    .frame(width: 24, height: 24)

                    Text(milestone.playerName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .nightCard()
    }
}

// MARK: - Detail

private struct DetailCard: View {
    let milestone: PlayerMilestone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(milestone.stat)
                    .font(.stat(20, weight: .heavy))
                    .foregroundStyle(Theme.lights)
                if let inning = milestone.inning {
                    Capsule()
                        .fill(Theme.cardElevated)
                        .frame(width: 38, height: 22)
                        .overlay(
                            Text(inning)
                                .font(.stat(11, weight: .heavy))
                                .foregroundStyle(Theme.textPrimary)
                        )
                }
                Spacer()
            }

            Text(milestone.detail)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }
}

// MARK: - Context

private struct ContextCard: View {
    let milestone: PlayerMilestone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Historical Context".uppercased())
                .font(.caps(11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.clay)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.lights)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.lights.opacity(0.16)))

                Text(milestone.context)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }
}

// MARK: - Game context

private struct GameContextCard: View {
    let game: AttendedGame
    let milestone: PlayerMilestone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You Were There".uppercased())
                .font(.caps(11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.clay)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                    Text(game.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                    Text(game.ballpark.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                    Text("Sect \(game.section) · Row \(game.row) · Seat \(game.seat)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }
}

private struct SourceLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .bold))
            Text("Career stats and milestones via the public MLB Stats API.")
                .font(.system(size: 11))
        }
        .foregroundStyle(Theme.textMuted)
        .frame(maxWidth: .infinity)
    }
}
