import SwiftUI
import MapKit

/// Continental map of all 30 MLB ballparks with journey route lines,
/// discovery facts, and next-park quest suggestions.
struct MapView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(StoreViewModel.self) private var storeKit
    @State private var showPaywall: Bool = false

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -96.0),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 55)
        )
    )
    @State private var selected: Ballpark?
    @State private var showDiscovery: Bool = false
    @State private var discoveryFact: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, selection: Binding(get: { selected?.id }, set: { id in
                if let id, let park = Ballpark.by(id: id) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        selected = park
                        discoveryFact = store.discoveryFor(park)
                        showDiscovery = true
                    }
                } else {
                    withAnimation { showDiscovery = false; selected = nil }
                }
            })) {
                // ── Pin annotations ──
                ForEach(Ballpark.all) { park in
                    Annotation(park.name, coordinate: park.coordinate, anchor: .center) {
                        BallparkPin(
                            park: park,
                            visited: store.visitedBallparkIds.contains(park.id),
                            count: visitCount(for: park),
                            isNext: nextParkIds.contains(park.id)
                        )
                    }
                    .tag(park.id)
                }

                // ── Journey route polyline ──
                let sequence = store.visitedParkSequence
                if sequence.count >= 2 {
                    let coords = sequence.map { $0.coordinate }
                    MapPolyline(coordinates: coords)
                        .stroke(
                            LinearGradient(
                                colors: [Theme.clay, Theme.lights],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: [8, 6],
                                dashPhase: 0
                            )
                        )
                }

                // ── Division overlay labels ──
                ForEach(divisionLabels, id: \.0) { name, center in
                    Annotation(name, coordinate: center, anchor: .center) {
                        Text(name)
                            .font(.caps(8, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.textMuted.opacity(0.5))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: selected) { _, park in
                if let park {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        position = .region(MKCoordinateRegion(
                            center: park.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 6)
                        ))
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        position = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -96.0),
                            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 55)
                        ))
                    }
                }
            }

            // ── Header overlay ──
            VStack(spacing: 0) {
                MapHeader(
                    visited: store.ballparkCount,
                    total: Ballpark.all.count,
                    games: store.totalGames
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }

            // ── Quest callout (next park suggestion) ──
            VStack {
                Spacer()
                if selected == nil, !store.ballparksRemaining.isEmpty {
                    NextParkBanner(parks: store.nearestUnvisitedParks(limit: 1)) { park in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            selected = park
                            discoveryFact = store.discoveryFor(park)
                            showDiscovery = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // ── Selected park card with discovery ──
            VStack {
                Spacer()
                if let park = selected {
                    BallparkSnapshotCard(
                        park: park,
                        games: gamesAt(park),
                        discovery: discoveryFact,
                        discovered: showDiscovery
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            selected = nil
                            showDiscovery = false
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: selected)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: storeKit)
        }
    }

    private func visitCount(for park: Ballpark) -> Int {
        store.completedGames.filter { $0.ballparkId == park.id }.count
    }

    private func gamesAt(_ park: Ballpark) -> [AttendedGame] {
        store.completedGames.filter { $0.ballparkId == park.id }
    }

    /// IDs of the top 3 nearest unvisited parks.
    private var nextParkIds: Set<String> {
        Set(store.nearestUnvisitedParks(limit: 3).map(\.id))
    }

    /// Division labels placed at the geographic centroid of each division.
    private var divisionLabels: [(String, CLLocationCoordinate2D)] { [
        ("AL EAST", CLLocationCoordinate2D(latitude: 41.2, longitude: -75.0)),
        ("AL CENTRAL", CLLocationCoordinate2D(latitude: 41.9, longitude: -88.0)),
        ("AL WEST", CLLocationCoordinate2D(latitude: 33.5, longitude: -110.0)),
        ("NL EAST", CLLocationCoordinate2D(latitude: 33.0, longitude: -82.0)),
        ("NL CENTRAL", CLLocationCoordinate2D(latitude: 40.5, longitude: -88.5)),
        ("NL WEST", CLLocationCoordinate2D(latitude: 36.0, longitude: -115.0)),
    ] }
}

// MARK: - Pin

private struct BallparkPin: View {
    let park: Ballpark
    let visited: Bool
    let count: Int
    let isNext: Bool
    @State private var pulse: Bool = false
    @State private var jiggle: Bool = false

    var body: some View {
        ZStack {
            // Fog glow ring for unvisited parks — subtle intrigue
            if !visited {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 38, height: 38)
                    .blur(radius: 6)
            }

            if visited {
                Circle()
                    .fill(Theme.lights.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .blur(radius: 10)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .opacity(pulse ? 0.55 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            }

            // Next park target ring
            if isNext && !visited {
                Circle()
                    .strokeBorder(Theme.lights.opacity(pulse ? 0.5 : 0.15), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.2 : 0.95)
                    .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
            }

            Circle()
                .fill(visited
                    ? AnyShapeStyle(LinearGradient(colors: [park.team.primary, park.team.primary.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(LinearGradient(colors: [Theme.cardElevated, Theme.card], startPoint: .top, endPoint: .bottom)))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().strokeBorder(visited ? Theme.lights : Color.white.opacity(0.18), lineWidth: visited ? 1.5 : 1)
                )
                .overlay(
                    Group {
                        if visited && count > 1 {
                            Text("\(count)")
                                .font(.stat(11, weight: .heavy))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: visited ? "baseball.fill" : "baseball")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(visited ? .white : Theme.textMuted)
                        }
                    }
                )
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Header

private struct MapHeader: View {
    let visited: Int
    let total: Int
    let games: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ballpark Map".uppercased())
                    .font(.caps(10, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(Theme.clay)
                Text("\(visited) of \(total) unlocked")
                    .font(.scoreboard(20))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("\(games) games")
                    .font(.stat(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Theme.cardElevated.opacity(0.85))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.night.opacity(0.85))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

// MARK: - Next park suggestion banner

private struct NextParkBanner: View {
    let parks: [Ballpark]
    let onTap: (Ballpark) -> Void
    @State private var slideIn: Bool = false

    var body: some View {
        if let park = parks.first {
            Button { onTap(park) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(park.team.primary.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Circle()
                            .strokeBorder(park.team.primary, lineWidth: 1.5)
                            .frame(width: 40, height: 40)
                        TeamLogoView(team: park.team, size: 28, showGloss: false)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next ballpark quest")
                            .font(.caps(9, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.clay)
                        Text(park.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.lights)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.card.opacity(0.9))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .offset(y: slideIn ? 0 : 60)
            .opacity(slideIn ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25)) {
                    slideIn = true
                }
            }
        }
    }
}

// MARK: - Snapshot card (enhanced)

private struct BallparkSnapshotCard: View {
    let park: Ballpark
    let games: [AttendedGame]
    let discovery: String
    let discovered: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip with team color
            HStack(spacing: 12) {
                Rectangle()
                    .fill(park.team.primary)
                    .frame(width: 4, height: 36)
                    .clipShape(.rect(cornerRadius: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(park.name)
                        .font(.scoreboard(18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(park.team.fullName) · \(park.city), \(park.state)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Facts row
            HStack(spacing: 18) {
                MapFact(label: "Opened", value: "\(park.opened)")
                MapFact(label: "Capacity", value: park.capacity.formatted(.number))
                MapFact(label: "Roof", value: park.roof.rawValue)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Discovery fact — fun thing to find at this park
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.lights)
                    Text("DID YOU KNOW?")
                        .font(.caps(9, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Theme.lights)
                }
                Text(discovery)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.lights.opacity(0.06))
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .opacity(discovered ? 1 : 0.6)

            Divider().background(Color.white.opacity(0.08)).padding(.vertical, 12)

            if games.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Theme.textMuted)
                    Text("You haven't been to \(park.nickname ?? park.name) yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your visits — \(games.count)".uppercased())
                        .font(.caps(10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Theme.clay)
                        .padding(.horizontal, 16)
                    ForEach(games.prefix(3)) { g in
                        NavigationLink(value: g) {
                            HStack(spacing: 10) {
                                Image(systemName: g.userWon ? "trophy.fill" : "circle.dotted")
                                    .font(.system(size: 11))
                                    .foregroundStyle(g.userWon ? Theme.lights : Theme.textMuted)
                                Text(g.date.formatted(Date.FormatStyle.dateTime.month(.abbreviated).day().year()))
                                    .font(.stat(12, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("vs \(g.userRootedForHome ? g.awayTeam.fullName : g.homeTeam.fullName)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(g.scoreString)
                                    .font(.stat(12, weight: .heavy))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}

private struct MapFact: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.stat(13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
