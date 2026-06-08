import SwiftUI
import MapKit

/// Continental map of all 30 MLB ballparks. Visited parks glow with stadium amber,
/// unvisited parks are dim outlines. Tapping a pin opens a snapshot card.
struct MapView: View {
    @Environment(DiaryStore.self) private var store

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -96.0),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 55)
        )
    )
    @State private var selected: Ballpark?

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, selection: Binding(get: { selected?.id }, set: { id in
                selected = id.flatMap { Ballpark.by(id: $0) }
            })) {
                ForEach(Ballpark.all) { park in
                    Annotation(park.name, coordinate: park.coordinate, anchor: .center) {
                        BallparkPin(
                            park: park,
                            visited: store.visitedBallparkIds.contains(park.id),
                            count: visitCount(for: park)
                        )
                    }
                    .tag(park.id)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(edges: .bottom)

            // Header overlay
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

            // Selected-park card
            VStack {
                Spacer()
                if let park = selected {
                    BallparkSnapshotCard(park: park, games: gamesAt(park)) {
                        selected = nil
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: selected)
        }
    }

    private func visitCount(for park: Ballpark) -> Int {
        store.completedGames.filter { $0.ballparkId == park.id }.count
    }

    private func gamesAt(_ park: Ballpark) -> [AttendedGame] {
        store.completedGames.filter { $0.ballparkId == park.id }
    }
}

// MARK: - Pin

private struct BallparkPin: View {
    let park: Ballpark
    let visited: Bool
    let count: Int
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            if visited {
                Circle()
                    .fill(Theme.lights.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .blur(radius: 10)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .opacity(pulse ? 0.55 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            }

            Circle()
                .fill(visited ? Theme.clayGradient : LinearGradient(colors: [Theme.cardElevated, Theme.card], startPoint: .top, endPoint: .bottom))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().strokeBorder(visited ? Theme.lights : Color.white.opacity(0.25), lineWidth: visited ? 1.5 : 1)
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

// MARK: - Snapshot card

private struct BallparkSnapshotCard: View {
    let park: Ballpark
    let games: [AttendedGame]
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
                                Text(g.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.stat(12, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("vs \(g.userRootedForHome ? g.awayTeam.name : g.homeTeam.name)")
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
