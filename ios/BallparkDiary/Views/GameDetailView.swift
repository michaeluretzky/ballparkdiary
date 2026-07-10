import SwiftUI
import UIKit

/// Detail screen for a single game: scoreboard, ticket stub with confirmation,
/// ballpark aerial, seat perspective, milestones, highlights, and game facts.
struct GameDetailView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(StoreViewModel.self) private var storeKit
    @Environment(\.dismiss) private var dismiss
    let game: AttendedGame
    @State private var shareUIImage: UIImage? = nil
    @State private var shareItem: ShareableImage? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var hasRenderedShareCard: Bool = false
    /// Timer-driven fact rotation for the BallparkPanel.
    @State private var factTimer: Timer? = nil
    @State private var factIndex: Int = 0

    /// Always-fresh copy of this game from the store. Pass this to every
    /// child panel so edits (seat, rooting, memory) are reflected immediately.
    private var liveGame: AttendedGame { store.game(id: game.id) ?? game }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Scoreboard(game: liveGame)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                TicketStubReal(game: liveGame)
                    .padding(.horizontal, 16)

                BallparkPanel(game: liveGame, factIndex: $factIndex)
                    .padding(.horizontal, 16)

                if liveGame.hasMemory {
                    MemoryPanel(game: liveGame)
                        .padding(.horizontal, 16)
                }

                if !liveGame.milestones.isEmpty {
                    if storeKit.isPremium {
                        MilestonesPanel(game: liveGame)
                            .padding(.horizontal, 16)
                    } else {
                        LockedMilestonesPanel(game: liveGame, onUnlock: { showPaywall = true })
                            .padding(.horizontal, 16)
                    }
                }

                if !liveGame.highlights.isEmpty {
                    HighlightsPanel(game: liveGame)
                        .padding(.horizontal, 16)
                }

                if !liveGame.isUpcoming {
                    FactsPanel(game: liveGame)
                        .padding(.horizontal, 16)

                    if !liveGame.pitching.isEmpty {
                        PitchingPanel(game: liveGame)
                            .padding(.horizontal, 16)
                    }
                }

                SourceRow(game: liveGame)
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
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Theme.lights)
                    }
                    .accessibilityLabel("Edit game")
                    if !liveGame.isUpcoming {
                        if storeKit.isPremium {
                            Button {
                                renderShareCardIfNeeded()
                                if let uiImage = shareUIImage {
                                    shareItem = ShareableImage(image: uiImage)
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(Theme.lights)
                            }
                            .accessibilityLabel("Share game card")
                        } else {
                            Button {
                                showPaywall = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14))
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(Theme.lights)
                            }
                            .accessibilityLabel("Share game card, requires Pro")
                        }
                    }
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.foul.opacity(0.8))
                    }
                    .accessibilityLabel("Delete game")
                }
            }
        }
        .confirmationDialog("Remove this game from your diary?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteGame(game.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This won't affect the original ticket or email.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: storeKit)
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.image])
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showEditSheet) {
            EditGameSheet(game: liveGame)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { startFactTimer() }
        .onDisappear { factTimer?.invalidate() }
    }

    /// Lazily render the share card only when the user first taps share.
    @MainActor
    internal func renderShareCardIfNeeded() {
        guard !hasRenderedShareCard || shareUIImage == nil else { return }
        hasRenderedShareCard = true
        let renderer = ImageRenderer(content: ShareableGameCard(game: liveGame).frame(width: 360, height: 480))
        renderer.scale = UIScreen.main.scale
        if let uiImage = renderer.uiImage {
            shareUIImage = uiImage
        }
    }

    private func startFactTimer() {
        factTimer?.invalidate()
        factTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                factIndex += 1
            }
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
                Text(team.abbreviation)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
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
    @Environment(DiaryStore.self) private var store
    let game: AttendedGame

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Text(game.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if game.firstPitchTempF > 0 {
                    Image(systemName: game.weather.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.lights)
                    Text("\(game.firstPitchTempF)°F")
                        .font(.stat(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
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
                        .fill(resultColor)
                        .frame(width: 6, height: 6)
                    Menu {
                        Picker("Rooted for", selection: Binding<Int>(
                            get: {
                                if game.userRootedForHome == nil { return 2 }
                                return game.userRootedForHome == true ? 0 : 1
                            },
                            set: { val in
                                switch val {
                                case 0: store.setRootedForHome(game.id, rootedForHome: true)
                                case 1: store.setRootedForHome(game.id, rootedForHome: false)
                                default: store.setRootedForHome(game.id, rootedForHome: nil)
                                }
                            }
                        )) {
                            Text(game.homeTeam.fullName).tag(0)
                            Text(game.awayTeam.fullName).tag(1)
                            Text("Neither").tag(2)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(resultText)
                                .font(.caps(11, weight: .heavy))
                                .tracking(1.5)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .heavy))
                        }
                        .foregroundStyle(resultColor)
                    }
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

    private var resultColor: Color {
        if game.userRootedForHome == nil { return Theme.textMuted }
        return game.userWon ? Theme.grass : Theme.foul
    }

    private var resultText: String {
        if game.userRootedForHome == nil {
            return "NEUTRAL · JUST WATCHING"
        }
        let team = game.userRootedForHome == true ? game.homeTeam : game.awayTeam
        let won = game.userWon
        return "\(won ? "WIN" : "LOSS") · ROOTED FOR \(team.fullName)"
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

                // Team logo area
                HStack(spacing: 0) {
                    Spacer()
                    TeamLogoView(team: game.homeTeam, size: 40, showGloss: false)
                        .padding(.trailing, 10)
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
    @Binding var factIndex: Int

    private var park: Ballpark { game.ballpark }

    /// Rotate through the park's discovery facts plus trivia.
    /// Shuffled on init so different sessions start on different facts.
    @State private var shuffledFacts: [String] = []

    private var currentFact: String {
        guard !shuffledFacts.isEmpty else { return park.trivia }
        return shuffledFacts[factIndex % shuffledFacts.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(game.homeTeam.primary)
                    .frame(width: 3, height: 18)
                    .clipShape(.capsule)
                Text(park.name)
                    .font(.headline(16))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            BallparkSnapshot(ballpark: park)
                .frame(height: 200)
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Stadium facts strip
            HStack(spacing: 16) {
                StadiumFact(label: "Capacity", value: park.capacity.formatted(.number))
                StadiumFact(label: "Opened", value: "\(park.opened)")
                StadiumFact(label: "Surface", value: park.surface)
                StadiumFact(label: "Roof", value: park.roof.rawValue)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Auto-rotating fun fact — changes every 6 seconds.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text(currentFact)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .id(factIndex) // triggers animation on change
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.lights.opacity(0.06))
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .animation(.easeInOut(duration: 0.4), value: factIndex)
            .onAppear {
                let discoveries = Ballpark.discoveries[park.id] ?? []
                shuffledFacts = [park.trivia] + discoveries.shuffled()
            }

            // Trivia
            Text(park.trivia)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .padding(16)
        }
        .nightCard()
    }
}

private struct StadiumFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.stat(13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

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
        .onAppear { if !reduceMotion { pulse = true } }
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
                            .foregroundStyle(Theme.textPrimary)
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
                if game.attendance > 0 {
                    Fact(label: "Attendance", value: game.attendance.formatted(.number))
                }
                if game.durationMinutes > 0 {
                    Fact(label: "Duration", value: durationString)
                }
                if game.firstPitchTempF > 0 {
                    Fact(label: "Weather", value: "\(game.weather.rawValue) · \(game.firstPitchTempF)°F")
                }
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

// MARK: - Pitching

private struct PitchingPanel: View {
    let game: AttendedGame

    private var homePitchers: [PitchingLine] {
        game.pitching.filter { $0.teamMlbId == game.homeTeam.mlbId }
    }
    private var awayPitchers: [PitchingLine] {
        game.pitching.filter { $0.teamMlbId == game.awayTeam.mlbId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pitching")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            if !awayPitchers.isEmpty {
                PitchingTeamHeader(team: game.awayTeam, label: "Away")
                ForEach(orderedPitchers(awayPitchers), id: \.playerMlbId) { line in
                    PitchingRow(line: line, team: game.awayTeam)
                }
            }

            if !homePitchers.isEmpty {
                PitchingTeamHeader(team: game.homeTeam, label: "Home")
                ForEach(orderedPitchers(homePitchers), id: \.playerMlbId) { line in
                    PitchingRow(line: line, team: game.homeTeam)
                }
            }
        }
        .padding(16)
        .nightCard()
    }

    /// Order: starter first (most IP), then by appearance order (assumed from API order),
    /// closers last (saves > 0). The API returns pitchers in order of appearance already.
    private func orderedPitchers(_ lines: [PitchingLine]) -> [PitchingLine] {
        lines.sorted { a, b in
            // Starters first (by IP, descending)
            let aIP = parseIP(a.inningsPitched)
            let bIP = parseIP(b.inningsPitched)
            if aIP >= 3 || bIP >= 3 {
                return aIP > bIP
            }
            // Within relievers, saves sort to the end
            if a.saves > 0 && b.saves == 0 { return false }
            if b.saves > 0 && a.saves == 0 { return true }
            return false
        }
    }

    private func parseIP(_ ip: String) -> Double {
        let parts = ip.split(separator: ".")
        guard let whole = Double(parts.first ?? "0") else { return 0 }
        let frac = parts.count > 1 ? (Double(parts[1]) ?? 0) / 3.0 : 0
        return whole + frac
    }
}

private struct PitchingTeamHeader: View {
    let team: Team
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(team.primary).frame(width: 18, height: 18)
                TeamLogoView(team: team, size: 14, showGloss: false)
            }
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.textMuted)
            Rectangle()
                .fill(Theme.textMuted.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }
}

private struct PitchingRow: View {
    let line: PitchingLine
    let team: Team

    private var roleLabel: String? {
        if line.completeGames >= 1 { return "CG" }
        if line.saves > 0 { return "SV" }
        if line.holds > 0 { return "HLD" }
        if line.isWinner { return "W" }
        if line.losses > 0 { return "L" }
        if parseIP(line.inningsPitched) >= 5 { return "SP" }
        return nil
    }

    private func parseIP(_ ip: String) -> Double {
        let parts = ip.split(separator: ".")
        guard let whole = Double(parts.first ?? "0") else { return 0 }
        let frac = parts.count > 1 ? (Double(parts[1]) ?? 0) / 3.0 : 0
        return whole + frac
    }

    var body: some View {
        HStack(spacing: 0) {
            // Role badge
            if let role = roleLabel {
                Text(role)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(team.primary)
                    .frame(width: 28, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(team.primary.opacity(0.15))
                    )
            } else {
                Color.clear.frame(width: 28, height: 18)
            }

            Spacer().frame(width: 8)

            // Name
            Text(line.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 6)

            // IP
            PitchingStatCell(label: "IP", value: line.inningsPitched)
            PitchingStatCell(label: "H", value: "\(line.hits)")
            PitchingStatCell(label: "R", value: "\(line.runs)")
            PitchingStatCell(label: "ER", value: "\(line.earnedRuns)")
            PitchingStatCell(label: "BB", value: "\(line.walks)")
            PitchingStatCell(label: "K", value: "\(line.strikeOuts)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.cardElevated.opacity(0.5))
        )
    }
}

private struct PitchingStatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.stat(11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(width: 28)
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
                .foregroundStyle(game.homeTeam.accentOnDark)
                .frame(width: 30, height: 30)
                .background(Circle().fill(game.homeTeam.accentOnDark.opacity(0.14)))
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

// MARK: - Edit Game Sheet

/// Lets the user update seat info and rooting preference on any verified
/// or unverified game. Changes are persisted immediately via the diary store.
private struct EditGameSheet: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let game: AttendedGame

    @State private var section: String
    @State private var row: String
    @State private var seat: String
    @State private var rootedForHome: Bool?
    @State private var rootedForNeither: Bool
    @State private var companions: String
    @State private var memory: String
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case sec, rw, st, comp, mem }

    init(game: AttendedGame) {
        self.game = game
        _section = State(initialValue: game.section == "—" ? "" : game.section)
        _row = State(initialValue: game.row == "—" ? "" : game.row)
        _seat = State(initialValue: game.seat == "—" ? "" : game.seat)
        _rootedForHome = State(initialValue: game.userRootedForHome)
        _rootedForNeither = State(initialValue: game.userRootedForHome == nil)
        _companions = State(initialValue: game.companions)
        _memory = State(initialValue: game.memory)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Matchup summary
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(game.awayTeam.primary)
                                    Circle().strokeBorder(game.awayTeam.secondary, lineWidth: 1.5)
                                    TeamLogoView(team: game.awayTeam, size: 40, showGloss: false)
                                }
                                .frame(width: 40, height: 40)
                                Text("@")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(Theme.textMuted)
                                ZStack {
                                    Circle().fill(game.homeTeam.primary)
                                    Circle().strokeBorder(game.homeTeam.secondary, lineWidth: 1.5)
                                    TeamLogoView(team: game.homeTeam, size: 40, showGloss: false)
                                }
                                .frame(width: 40, height: 40)
                            }
                            Text(game.ballpark.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Text(game.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .nightCard()

                        // Seat info
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SEAT INFO".uppercased())
                                .font(.caps(10, weight: .heavy))
                                .tracking(2.2)
                                .foregroundStyle(Theme.clay)

                            HStack(spacing: 8) {
                                LabeledInput(label: "Section", text: $section)
                                    .focused($focusedField, equals: .sec)
                                LabeledInput(label: "Row", text: $row)
                                    .focused($focusedField, equals: .rw)
                                LabeledInput(label: "Seat", text: $seat)
                                    .focused($focusedField, equals: .st)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nightCard()

                        // Rooting preference
                        VStack(alignment: .leading, spacing: 10) {
                            Text("YOU ROOTED FOR".uppercased())
                                .font(.caps(10, weight: .heavy))
                                .tracking(2.2)
                                .foregroundStyle(Theme.clay)

                            Picker("Rooted for", selection: Binding<Int>(
                                get: {
                                    if rootedForNeither { return 2 }
                                    return rootedForHome == true ? 0 : 1
                                },
                                set: { val in
                                    switch val {
                                    case 0: rootedForHome = true; rootedForNeither = false
                                    case 1: rootedForHome = false; rootedForNeither = false
                                    default: rootedForHome = nil; rootedForNeither = true
                                    }
                                }
                            )) {
                                Text(game.homeTeam.fullName).tag(0)
                                Text(game.awayTeam.fullName).tag(1)
                                Text("Neither").tag(2)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nightCard()

                        // Memory section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MEMORIES".uppercased())
                                .font(.caps(10, weight: .heavy))
                                .tracking(2.2)
                                .foregroundStyle(Theme.clay)
                            LabeledInput(label: "Went with", text: $companions)
                                .focused($focusedField, equals: .comp)
                            LabeledInput(label: "Notes", text: $memory, multiline: true, autocap: false)
                                .focused($focusedField, equals: .mem)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nightCard()

                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Edit Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.nightDeep.opacity(0.95), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = section.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : section
                        let r = row.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : row
                        let se = seat.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : seat
                        store.setSeatInfo(game.id, section: s, row: r, seat: se)
                        let newRoot: Bool? = rootedForNeither ? nil : rootedForHome
                        if newRoot != game.userRootedForHome {
                            store.setRootedForHome(game.id, rootedForHome: newRoot)
                        }
                        store.setMemory(game.id, companions: companions.trimmingCharacters(in: .whitespaces), memory: memory.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .fontWeight(.heavy)
                    .foregroundStyle(Theme.lights)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { focusedField = nil }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - Memory panel

private struct MemoryPanel: View {
    let game: AttendedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.clay)
                Text("Memories")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }

            if !game.companions.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.lights)
                    Text("Went with")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text(game.companions.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }

            if !game.memory.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !game.companions.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.lights)
                            Text("Notes")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                            Spacer()
                        }
                    }
                    Text(game.memory.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .nightCard()
    }
}
