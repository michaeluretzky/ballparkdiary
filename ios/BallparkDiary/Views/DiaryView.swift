import SwiftUI

/// Chronological list of attended games with ballpark aerial hero photos,
/// compact scores, confirmation numbers, and subtle parallax on scroll.
struct DiaryView: View {
    @Environment(DiaryStore.self) private var store
    @State private var showAddSheet = false
    @State private var gameToDelete: AttendedGame? = nil
    @State private var showDeleteConfirm = false
    @State private var navigationPath = NavigationPath()
    @State private var yearFilter: Int? = nil
    @State private var teamFilter: String? = nil

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.nightDeep.opacity(0.95))
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: 18) {
                    if store.games.isEmpty {
                        EmptyDiaryView()
                            .padding(.horizontal, 16)
                            .padding(.top, 40)
                    } else {
                        Text("Diary")
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        DiaryHeader()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        DiaryFilterBar(
                            selectedYear: $yearFilter,
                            selectedTeam: $teamFilter,
                            availableYears: availableYears,
                            availableTeams: availableTeams
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                        if !store.upcomingGames.isEmpty && yearFilter == nil && teamFilter == nil {
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
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            gameToDelete = game
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }

                        ForEach(Array(filteredGroupedGames.enumerated()), id: \.element.0) { _, group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Rectangle()
                                        .fill(store.favoriteTeam.primary.opacity(0.6))
                                        .frame(width: 32, height: 3)
                                        .clipShape(.capsule)
                                    Text(group.0)
                                        .font(.system(size: 16, weight: .black))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 10)

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
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            gameToDelete = game
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 40)

                    if !store.games.isEmpty {
                        Text("Ballpark Diary is an independent app. Not affiliated with or endorsed by Major League Baseball, any MLB team, or any player.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)
                    }
                }
            }
            .background {
                Theme.nightGradient.ignoresSafeArea()
                Theme.nightVignette.ignoresSafeArea()
            }
            .navigationTitle("Diary")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.nightDeep.opacity(0.95), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(store.favoriteTeam.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(store.favoriteTeam.primary.opacity(0.15))
                            )
                    }
                }
            }
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
            .confirmationDialog("Remove this game from your diary?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let game = gameToDelete {
                        withAnimation { store.deleteGame(game.id) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This won't affect the original ticket.")
            }
            .sheet(isPresented: $showAddSheet) {
                AddGameOptionsView()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                navigateToImportedGameIfNeeded()
            }
            .onChange(of: store.lastImportedGameId) { _, gameId in
                guard let gameId else { return }
                navigateToImportedGame(gameId: gameId)
            }
        }
    }

    private var groupedGames: [(String, [AttendedGame])] {
        let groups = Dictionary(grouping: store.completedGames) { g -> Int in
            Calendar.current.component(.year, from: g.date)
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { ("\($0.key)", $0.value.sorted { $0.date > $1.date }) }
    }

    private var filteredGroupedGames: [(String, [AttendedGame])] {
        var result = groupedGames
        if let year = yearFilter {
            result = result.filter { $0.0 == "\(year)" }
        }
        if let teamId = teamFilter {
            result = result.map { group in
                (group.0, group.1.filter { g in
                    g.homeTeamId == teamId || g.awayTeamId == teamId
                })
            }.filter { !$0.1.isEmpty }
        }
        return result
    }

    private var availableYears: [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for g in store.completedGames {
            let year = Calendar.current.component(.year, from: g.date)
            counts[year, default: 0] += 1
        }
        return counts.map { (year: $0.key, count: $0.value) }.sorted { $0.year > $1.year }
    }

    private var availableTeams: [(team: Team, count: Int)] {
        var seen: [String: Int] = [:]
        for g in store.completedGames {
            seen[g.homeTeamId, default: 0] += 1
            seen[g.awayTeamId, default: 0] += 1
        }
        return seen.compactMap { id, count in
            Team.by(id: id).map { ($0, count) }
        }.sorted { $0.count > $1.count }
    }

    /// Navigate to a freshly imported game so the user can verify the data.
    /// Called both from `onAppear` (the game may have been imported before
    /// this view mounted) and `onChange` (imported while this view is visible).
    private func navigateToImportedGame(gameId: UUID) {
        guard let game = store.game(id: gameId) else { return }
        navigationPath.append(game)
        store.lastImportedGameId = nil
    }

    private func navigateToImportedGameIfNeeded() {
        guard let gameId = store.lastImportedGameId else { return }
        navigateToImportedGame(gameId: gameId)
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
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
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
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                HStack(spacing: 6) {
                    TeamChip(team: game.awayTeam, primary: false)
                    Text("@")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.5))
                    TeamChip(team: game.homeTeam, primary: true)
                        .layoutPriority(1)
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
                        .foregroundStyle(.white)
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
                .font(.headline(14, weight: .black))
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
                .font(.caps(11, weight: .heavy))
                .tracking(1)
                .foregroundStyle(.white)
            Text(game.date.formatted(.dateTime.day()))
                .font(.stat(20, weight: .heavy))
                .foregroundStyle(.white)
            Text(String(Calendar.current.component(.year, from: game.date)))
                .font(.stat(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct TeamChip: View {
    let team: Team
    let primary: Bool

    var body: some View {
        HStack(spacing: 7) {
            TeamLogoView(team: team, size: 30, showGloss: false)
            Text(team.fullName)
                .font(.stat(11, weight: .heavy))
                .foregroundStyle(primary ? .white : .white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Empty diary

private struct EmptyDiaryView: View {
    @Environment(DiaryStore.self) private var store
    @State private var ballSpin: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 30)

            // Rotating baseball — continuous spin with a soft glow behind it
            ZStack {
                // Soft amber glow ring that subtly breathes
                Circle()
                    .fill(Theme.lights.opacity(0.12))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)

                BaseballMark(size: 90)
                    .rotationEffect(.degrees(ballSpin))
                    .shadow(color: Theme.lights.opacity(0.35), radius: 20, y: 6)
            }
            .padding(.bottom, 4)

            Text("Your diary is waiting.")
                .font(.scoreboard(24, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Share a ticket screenshot or add a game by hand to begin building your ballpark history.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
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
                .foregroundStyle(.white.opacity(0.7))
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

// MARK: - Filters (dropdown menus)

private struct DiaryFilterBar: View {
    @Binding var selectedYear: Int?
    @Binding var selectedTeam: String?
    let availableYears: [(year: Int, count: Int)]
    let availableTeams: [(team: Team, count: Int)]

    private var yearLabel: String {
        if let y = selectedYear,
           let match = availableYears.first(where: { $0.year == y }) {
            return "\(match.year) (\(match.count))"
        }
        return "All Years"
    }

    private var teamLabel: String {
        if let id = selectedTeam,
           let match = availableTeams.first(where: { $0.team.id == id }) {
            return "\(match.team.abbreviation) (\(match.count))"
        }
        return "All Teams"
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    setYear(nil)
                } label: {
                    if selectedYear == nil { Label("All Years", systemImage: "checkmark") }
                    else { Text("All Years") }
                }
                ForEach(availableYears, id: \.year) { item in
                    Button {
                        setYear(item.year)
                    } label: {
                        if selectedYear == item.year {
                            Label("\(item.year) (\(item.count))", systemImage: "checkmark")
                        } else {
                            Text("\(item.year) (\(item.count))")
                        }
                    }
                }
            } label: {
                FilterDropdownLabel(
                    icon: "calendar",
                    text: yearLabel,
                    isActive: selectedYear != nil
                )
            }

            Menu {
                Button {
                    setTeam(nil)
                } label: {
                    if selectedTeam == nil { Label("All Teams", systemImage: "checkmark") }
                    else { Text("All Teams") }
                }
                ForEach(availableTeams, id: \.team.id) { item in
                    Button {
                        setTeam(item.team.id)
                    } label: {
                        if selectedTeam == item.team.id {
                            Label("\(item.team.abbreviation) — \(item.team.fullName) (\(item.count))", systemImage: "checkmark")
                        } else {
                            Text("\(item.team.abbreviation) — \(item.team.fullName) (\(item.count))")
                        }
                    }
                }
            } label: {
                FilterDropdownLabel(
                    icon: "baseball",
                    text: teamLabel,
                    isActive: selectedTeam != nil
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func setYear(_ year: Int?) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedYear = year
        }
    }

    private func setTeam(_ id: String?) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedTeam = id
        }
    }
}

private struct FilterDropdownLabel: View {
    let icon: String
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(isActive ? .white : .white.opacity(0.7))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isActive ? Theme.clay : Theme.cardElevated)
        )
        .overlay(
            Capsule()
                .strokeBorder(isActive ? Theme.clay.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
