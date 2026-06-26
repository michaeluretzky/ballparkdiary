import SwiftUI
import UIKit

/// Detail screen for a single game: scoreboard, ticket stub with confirmation,
/// ballpark aerial, seat perspective, milestones, highlights, and game facts.
struct GameDetailView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(StoreViewModel.self) private var storeKit
    let game: AttendedGame
    @State private var shareImage: Image? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var showPaywall: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Scoreboard(game: game)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                TicketStubReal(game: game)
                    .padding(.horizontal, 16)

                BallparkPanel(game: game)
                    .padding(.horizontal, 16)

                if !game.milestones.isEmpty {
                    if storeKit.isPremium {
                        MilestonesPanel(game: game)
                            .padding(.horizontal, 16)
                    } else {
                        LockedMilestonesPanel(game: game, onUnlock: { showPaywall = true })
                            .padding(.horizontal, 16)
                    }
                }

                if !game.highlights.isEmpty {
                    HighlightsPanel(game: game)
                        .padding(.horizontal, 16)
                }

                if !game.isUpcoming {
                    FactsPanel(game: game)
                        .padding(.horizontal, 16)
                }

                SourceRow(game: game)
                    .padding(.horizontal, 16)

                Color.clear.frame(height: 30)
            }
            .padding(.top, 8)
        }
        .background {
            Theme.nightGradient.ignoresSafeArea()
            Theme.nightVignette.ignoresSafeArea()
        }
        .navigationTitle(game.ballpark.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Theme.nightDeep.opacity(0.95), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if let shareImage {
                        if storeKit.isPremium {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview("\(game.awayTeam.fullName) @ \(game.homeTeam.fullName)", image: shareImage)
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        } else {
                            Button { showPaywall = true } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14))
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(Theme.lights)
                            }
                        }
                    }
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.foul.opacity(0.8))
                    }
                }
            }
        }
        .confirmationDialog("Remove this game from your diary?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteGame(game.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This won't affect the original ticket or email.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: storeKit)
        }
        .task { renderShareCard() }
    }

    @MainActor
    private func renderShareCard() {
        let renderer = ImageRenderer(content: ShareableGameCard(game: game).frame(width: 360, height: 480))
        renderer.scale = UIScreen.main.scale
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }
}

// MARK: - Shareable card

private struct ShareableGameCard: View {
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 18) {
            Text("BALLPARK DIARY")
                .font(.caps(13, weight: .heavy))
                .tracking(6)
                .foregroundStyle(Theme.clay)

            Text(game.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)))
                .font(.caps(11, weight: .heavy))
                .tracking(3)
                .foregroundStyle(Theme.lights)

            HStack(spacing: 18) {
                cardTeam(game.awayTeam, score: game.awayScore, winner: !game.isUpcoming && game.awayScore > game.homeScore)
                Text("@")
                    .font(.scoreboard(20, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                cardTeam(game.homeTeam, score: game.homeScore, winner: !game.isUpcoming && game.homeScore > game.awayScore)
            }
            .padding(.vertical, 8)

            Text(game.ballpark.name)
                .font(.scoreboard(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("\(game.ballpark.city), \(game.ballpark.state)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            if game.isUpcoming {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text("Going to this one")
                }
                .font(.caps(12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.lights)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: game.userWon ? "trophy.fill" : "baseball.fill")
                    Text(game.userWon ? "Took the W" : "Caught the L")
                }
                .font(.caps(12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(game.userWon ? Theme.grass : Theme.foul)
            }

            Spacer(minLength: 0)

            BaseballMark(size: 44)
        }
        .padding(28)
        .frame(width: 360, height: 480)
        .background(Theme.nightGradient)
    }

    private func cardTeam(_ team: Team, score: Int, winner: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(team.primary)
                Circle().strokeBorder(team.secondary, lineWidth: 2)
                TeamLogoView(team: team, size: 60)
            }
            .frame(width: 60, height: 60)
            Text(game.isUpcoming ? "–" : "\(score)")
                .font(.scoreboard(46, weight: .black))
                .foregroundStyle(winner ? Theme.textPrimary : Theme.textMuted)
        }
    }
}

// MARK: - Scoreboard

private struct Scoreboard: View {
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Text(game.date.formatted(date: .complete, time: .omitted))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: game.weather.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("\(game.firstPitchTempF)°F")
                    .font(.stat(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 12) {
                TeamColumn(team: game.awayTeam, score: game.awayScore, isWinner: !game.isUpcoming && game.awayScore > game.homeScore, hideScore: game.isUpcoming)
                Text("vs")
                    .font(.scoreboard(14, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                TeamColumn(team: game.homeTeam, score: game.homeScore, isWinner: !game.isUpcoming && game.homeScore > game.awayScore, hideScore: game.isUpcoming)
            }

            if game.isUpcoming {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Theme.lights)
                        .frame(width: 6, height: 6)
                    Text("UPCOMING · FIRST PITCH \(game.date.formatted(.dateTime.hour().minute()))")
                        .font(.caps(11, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Theme.lights)
                    Spacer()
                    Text("Pull down on your diary to update the score")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(game.userWon ? Theme.grass : Theme.foul)
                        .frame(width: 6, height: 6)
                    Text(resultText)
                        .font(.caps(11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(game.userWon ? Theme.grass : Theme.foul)
                    Spacer()
                    if game.attendance > 0 || game.durationMinutes > 0 {
                        Text(metaString)
                            .font(.stat(11, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .nightCard()
    }

    private var metaString: String {
        var parts: [String] = []
        if game.durationMinutes > 0 { parts.append(durationString) }
        if game.attendance > 0 { parts.append("\(game.attendance.formatted(.number)) fans") }
        return parts.joined(separator: " · ")
    }

    private var resultText: String {
        let team = game.userRootedForHome ? game.homeTeam : game.awayTeam
        return "\(game.userWon ? "WIN" : "LOSS") · ROOTED FOR \(team.fullName)"
    }

    private var durationString: String {
        let h = game.durationMinutes / 60
        let m = game.durationMinutes % 60
        return "\(h)h \(m)m"
    }
}

private struct TeamColumn: View {
    let team: Team
    let score: Int
    let isWinner: Bool
    var hideScore: Bool = false
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(team.primary)
                Circle().strokeBorder(team.secondary, lineWidth: 2)
                TeamLogoView(team: team, size: 56)
            }
            .frame(width: 56, height: 56)

            Text(hideScore ? "–" : "\(score)")
                .font(.scoreboard(48, weight: .black))
                .foregroundStyle(isWinner ? Theme.textPrimary : Theme.textMuted)

            Text(team.fullName)
                .font(.caps(10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ticket stub (realism)

private struct TicketStubReal: View {
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 0) {
            // Team-colored top band with notches
            ZStack {
                Rectangle()
                    .fill(game.homeTeam.primary)
                    .frame(height: 22)

                // Perforation notches along the top edge
                HStack(spacing: 0) {
                    ForEach(0..<14, id: \.self) { i in
                        Circle()
                            .fill(Theme.parchment)
                            .frame(width: 7, height: 7)
                            .offset(y: -3.5)
                        if i < 13 { Spacer() }
                    }
                }
                .padding(.horizontal, 8)

                // Small logo area
                HStack(spacing: 0) {
                    Spacer()
                    TeamLogoView(team: game.homeTeam, size: 18, showGloss: false)
                        .padding(.trailing, 12)
                }
            }

            // Main stub body
            HStack(spacing: 0) {
                // Left content
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(game.awayTeam.fullName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.parchmentInk)
                            .lineLimit(1)
                        Text("@")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.parchmentInk.opacity(0.5))
                        Text(game.homeTeam.fullName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.parchmentInk)
                            .lineLimit(1)
                        if !game.isUpcoming {
                            Text(game.scoreString)
                                .font(.stat(12, weight: .heavy))
                                .foregroundStyle(Theme.parchmentInk.opacity(0.6))
                        }
                    }

                    Text(game.ballpark.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.parchmentInk)
                        .lineLimit(1)

                    HStack(spacing: 16) {
                        StubField(label: "SEC", value: game.section)
                        StubField(label: "ROW", value: game.row)
                        StubField(label: "SEAT", value: game.seat)
                    }
                    .padding(.top, 2)

                    // Faux barcode strip
                    FauxBarcode()
                        .padding(.top, 4)

                    // Confirmation in monospaced ticketing style
                    if let conf = game.confirmationNumber {
                        HStack(spacing: 4) {
                            Text("CONF#")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.parchmentInk.opacity(0.45))
                            Text(conf)
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Theme.parchmentInk.opacity(0.75))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Tear line with real perforation notches
                TearPerforation()
                    .fill(Theme.parchmentInk.opacity(0.3))
                    .frame(width: 12)

                // Right stub (tear-off portion)
                VStack(spacing: 4) {
                    Text("ADMIT")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Theme.parchmentInk.opacity(0.45))
                    Text("ONE")
                        .font(.scoreboard(16, weight: .black))
                        .foregroundStyle(Theme.parchmentInk)
                    if !game.verified {
                        Text("UNVERIFIED")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(Theme.foul.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.foul.opacity(0.3)))
                    }
                    Text(game.date.formatted(.dateTime.day()))
                        .font(.scoreboard(12, weight: .heavy))
                        .foregroundStyle(Theme.parchmentInk.opacity(0.6))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .frame(width: 70)
                .background(Theme.parchmentInk.opacity(0.03))
            }
        }
        .background(Theme.parchment)
        .parchmentTexture()
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
    }
}

/// Perforation notches along the tear line — alternating circles punched out.
private struct TearPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let notchCount = 7
        let notchDiam: CGFloat = 5
        let spacing = rect.height / CGFloat(notchCount)
        for i in 0..<notchCount {
            let y = spacing * (CGFloat(i) + 0.5)
            let notch = CGRect(x: rect.midX - notchDiam / 2, y: y - notchDiam / 2,
                               width: notchDiam, height: notchDiam)
            p.addEllipse(in: notch)
        }
        // Vertical line connecting the notches
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// Simple faux barcode for the ticket stub.
private struct FauxBarcode: View {
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<22, id: \.self) { i in
                Rectangle()
                    .fill(Theme.parchmentInk.opacity(0.25))
                    .frame(width: [1, 2, 3, 1, 4, 1, 2, 3, 1, 2, 1, 2, 3, 1, 4, 1, 2, 1, 3, 2, 1, 2][i],
                           height: 16)
            }
        }
    }
}

private struct StubField: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.parchmentInk.opacity(0.4))
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.parchmentInk)
        }
    }
}

// MARK: - Ballpark panel

private struct BallparkPanel: View {
    let game: AttendedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(game.homeTeam.primary)
                    .frame(width: 3, height: 18)
                    .clipShape(.capsule)
                Text(game.ballpark.nickname ?? game.ballpark.name)
                    .font(.headline(16))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            BallparkSnapshot(ballpark: game.ballpark)
                .frame(height: 200)
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Text(game.ballpark.trivia)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .padding(16)
        }
        .nightCard()
    }
}

// MARK: - Milestones (medallions)

private struct MilestonesPanel: View {
    let game: AttendedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("Career Milestones")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Spacer()
                Text("You were there")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.lights)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Theme.lights.opacity(0.16))
                    )
            }

            VStack(spacing: 10) {
                ForEach(game.milestones) { milestone in
                    NavigationLink(value: milestone) {
                        MilestoneMedallion(milestone: milestone)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .nightCardDeep()
        .navigationDestination(for: PlayerMilestone.self) { milestone in
            MilestoneDetailView(milestone: milestone, game: game)
        }
    }
}

private struct MilestoneMedallion: View {
    let milestone: PlayerMilestone
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Medallion — custom drawn instead of SF Symbol circle
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Theme.lights, Theme.clay, Theme.lights],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
                    .frame(width: 48, height: 48)

                // Inner badge
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.clay.opacity(0.7), Theme.clayDeep.opacity(0.9)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 24
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: milestone.category.symbol)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .scaleEffect(pulse ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(milestone.playerName) · \(milestone.stat)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardElevated)
        )
        .onAppear { pulse = true }
    }
}

// MARK: - Highlights

private struct HighlightsPanel: View {
    let game: AttendedGame
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scoring plays")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                ForEach(game.highlights, id: \.self) { h in
                    HStack(alignment: .top, spacing: 12) {
                        Text(h.inning)
                            .font(.stat(11, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.cardElevated))

                        Image(systemName: h.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(h.kind == .walkoff ? Theme.lights : TeamColors.from(team: game.homeTeam).primary)
                            .frame(width: 24, height: 24)

                        Text(h.description)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .nightCard()
    }
}

// MARK: - Facts

private struct FactsPanel: View {
    let game: AttendedGame
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Box score")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Fact(label: "Total Runs", value: "\(game.totalRuns)")
                Fact(label: "Attendance", value: game.attendance.formatted(.number))
                Fact(label: "Duration", value: durationString)
                Fact(label: "Weather", value: "\(game.weather.rawValue) · \(game.firstPitchTempF)°F")
            }
        }
        .padding(16)
        .nightCard()
    }

    private var durationString: String {
        "\(game.durationMinutes / 60)h \(game.durationMinutes % 60)m"
    }
}

private struct Fact: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.stat(15, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Theme.cardElevated)
        )
    }
}

// MARK: - Locked milestones (pro gate)

private struct LockedMilestonesPanel: View {
    let game: AttendedGame
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Text("\(game.milestones.count) Milestone\(game.milestones.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.lights)
            }

            Button(action: onUnlock) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Unlock with Pro to see player milestones")
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
        .nightCardDeep()
    }
}

// MARK: - Source row

private struct SourceRow: View {
    let game: AttendedGame

    private var isManual: Bool { game.source.contains("Manual") }
    private var icon: String { isManual ? "square.and.pencil" : "square.and.arrow.down.fill" }
    private var caption: String { isManual ? "Added by hand" : "Imported from a shared ticket" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TeamColors.from(team: game.homeTeam).primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(TeamColors.from(team: game.homeTeam).primary.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Text(game.source)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if !game.verified && !game.isUpcoming {
                Image(systemName: "questionmark.diamond")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted.opacity(0.6))
            }
        }
        .padding(12)
        .nightCardDeep(cornerRadius: 14)
    }
}
