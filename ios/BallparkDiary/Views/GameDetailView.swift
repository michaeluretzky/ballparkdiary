import SwiftUI
import UIKit

/// Detail screen for a single attended game: scoreboard, ticket, ballpark, highlights.
struct GameDetailView: View {
    let game: AttendedGame
    @State private var shareImage: Image? = nil

    var body: some View {
        ZStack {
            Color.red.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // VERIFICATION BANNER
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.yellow)
                        Text("🔥 NEW DETAIL VIEW 🔥")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.yellow)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.yellow, lineWidth: 3))
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    Scoreboard(game: game)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    TicketStub(game: game)
                        .padding(.horizontal, 16)

                    BallparkPanel(game: game)
                        .padding(.horizontal, 16)

                    if !game.milestones.isEmpty {
                        MilestonesPanel(game: game)
                            .padding(.horizontal, 16)
                    }

                    if !game.highlights.isEmpty {
                        HighlightsPanel(game: game)
                            .padding(.horizontal, 16)
                    }

                    if !game.isUpcoming {
                        FactsPanel(game: game)
                            .padding(.horizontal, 16)
                    }

                    SourceEmailRow(game: game)
                        .padding(.horizontal, 16)

                    Color.clear.frame(height: 30)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("GAME DETAIL — NEW")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.red, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview("\(game.awayTeam.abbreviation) @ \(game.homeTeam.abbreviation)", image: shareImage)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
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

/// A polished, image-exportable summary of a single game for sharing.
private struct ShareableGameCard: View {
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 18) {
            Text("BALLPARK DIARY")
                .font(.caps(13, weight: .heavy))
                .tracking(6)
                .foregroundStyle(Theme.clay)

            Text(game.date.formatted(date: .abbreviated, time: .omitted).uppercased())
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
                .padding(.top, 4)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: game.userWon ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    Text(game.userWon ? "I saw a win" : "I was there for the loss")
                }
                .font(.caps(12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(game.userWon ? Theme.grass : Theme.foul)
                .padding(.top, 4)
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
                Text(team.abbreviation)
                    .font(.stat(16, weight: .heavy))
                    .foregroundStyle(.white)
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
            // Date / venue strip
            HStack(spacing: 6) {
                Text(game.date.formatted(date: .complete, time: .omitted).uppercased())
                    .font(.caps(10, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Theme.clay)
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
                        .tracking(2)
                        .foregroundStyle(game.userWon ? Theme.grass : Theme.foul)
                    Spacer()
                    if game.attendance > 0 || game.durationMinutes > 0 {
                        Text(metaString)
                            .font(.stat(11, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
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
        return "\(game.userWon ? "WIN" : "LOSS") · CHEERED FOR \(team.abbreviation)"
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
                Text(team.abbreviation)
                    .font(.stat(15, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            Text(hideScore ? "–" : "\(score)")
                .font(.scoreboard(48, weight: .black))
                .foregroundStyle(isWinner ? Theme.textPrimary : Theme.textMuted)

            Text(team.name.isEmpty ? team.city : team.name)
                .font(.caps(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ticket stub

private struct TicketStub: View {
    let game: AttendedGame
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("TICKET STUB")
                        .font(.caps(10, weight: .heavy))
                        .tracking(2.5)
                        .foregroundStyle(Theme.parchmentInk.opacity(0.7))
                    if let conf = game.confirmationNumber {
                        Text("#\(conf)")
                            .font(.caps(8, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(Theme.clay)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Theme.clay.opacity(0.15))
                            )
                    }
                }
                Text(game.ballpark.name)
                    .font(.scoreboard(18, weight: .bold))
                    .foregroundStyle(Theme.parchmentInk)
                    .lineLimit(1)
                HStack(spacing: 16) {
                    StubField(label: "Sect", value: game.section)
                    StubField(label: "Row", value: game.row)
                    StubField(label: "Seat", value: game.seat)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Tear edge
            TearLine()
                .stroke(Theme.parchmentInk.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 1)

            VStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.clay)
                Text("ADMIT")
                    .font(.caps(8, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.parchmentInk.opacity(0.6))
                Text("ONE")
                    .font(.scoreboard(14, weight: .bold))
                    .foregroundStyle(Theme.parchmentInk)
            }
            .padding(14)
            .frame(width: 90)
        }
        .background(Theme.parchment)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.parchmentInk.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

private struct TearLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

private struct StubField: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caps(8, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.parchmentInk.opacity(0.55))
            Text(value)
                .font(.stat(13, weight: .heavy))
                .foregroundStyle(Theme.parchmentInk)
        }
    }
}

// MARK: - Ballpark panel with aerial + seat view

private struct BallparkPanel: View {
    let game: AttendedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.clay)
                Text(game.ballpark.nickname ?? game.ballpark.name)
                    .font(.scoreboard(16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Bright colored block instead of MapKit
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(height: 180)
                .overlay {
                    Text(game.ballpark.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .clipShape(.rect(cornerRadius: 8))
                }
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Seat perspective — only when ticket has real seat info
            if game.hasSeatInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "eyes")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.lights)
                        Text("VIEW FROM YOUR SEAT")
                            .font(.caps(9, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.lights.opacity(0.8))
                        Spacer()
                        Text("Section \(game.section)")
                            .font(.stat(10, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    SeatPerspectiveView(game: game)
                        .frame(height: 140)
                        .clipShape(.rect(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            Text(game.ballpark.trivia)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .padding(16)
        }
        .nightCard()
    }
}

// MARK: - Milestones

private struct MilestonesPanel: View {
    let game: AttendedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("Career Milestones".uppercased())
                    .font(.caps(11, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.clay)
                Spacer()
                Text("YOU SAW THIS")
                    .font(.caps(9, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Theme.lights)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Theme.lights.opacity(0.16))
                    )
            }

            VStack(spacing: 10) {
                ForEach(game.milestones) { milestone in
                    NavigationLink(value: milestone) {
                        MilestoneRow(milestone: milestone)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .nightCard()
        .navigationDestination(for: PlayerMilestone.self) { milestone in
            MilestoneDetailView(milestone: milestone, game: game)
        }
    }
}

private struct MilestoneRow: View {
    let milestone: PlayerMilestone

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.clayGradient)
                Circle().strokeBorder(Theme.lights, lineWidth: 1.5)
                Image(systemName: milestone.category.symbol)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

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
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.lights.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Highlights

private struct HighlightsPanel: View {
    let game: AttendedGame
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights".uppercased())
                .font(.caps(11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.clay)

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
                            .foregroundStyle(h.kind == .walkoff ? Theme.lights : Theme.clay)
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
            Text("Game Facts".uppercased())
                .font(.caps(11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.clay)
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
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.2)
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

// MARK: - Source email

private struct SourceEmailRow: View {
    let game: AttendedGame

    private var isManual: Bool { game.source == "Manual entry" }
    private var icon: String { isManual ? "square.and.pencil" : "square.and.arrow.down.fill" }
    private var caption: String { isManual ? "Added by hand" : "Imported from a shared ticket" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.clay)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.clay.opacity(0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(caption.uppercased())
                    .font(.caps(9, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textMuted)
                Text(game.source)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .nightCard(cornerRadius: 14)
    }
}

// Source extension to surface the ticketing platform on the email row.
extension AttendedGame {
    var ticketSource: String { source }
}
