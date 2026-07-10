import SwiftUI
import CoreLocation

/// Pro feature: chains nearby unvisited ballparks that have home games on
/// consecutive (or near-consecutive) days into a suggested weekend route.
/// Anchored on the user's real location when shared, otherwise the favorite
/// team's home park.
struct RoadTripCard: View {
    @Environment(DiaryStore.self) private var store
    @Environment(LocationService.self) private var location

    @State private var stops: [RoadTripStop] = []
    @State private var isLoading: Bool = true

    private var anchor: CLLocation {
        location.lastLocation ?? store.questAnchorLocation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.clay)
                Text("Road-trip builder")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                proTag
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.textMuted)
                    Text("Checking schedules at nearby parks…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if stops.isEmpty {
                Text("No multi-park windows found in the next 60 days. Check back as new schedules post.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tripSummary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        RoadTripStopRow(
                            stop: stop,
                            index: index + 1,
                            legMiles: legMiles(to: index)
                        )
                        if index < stops.count - 1 {
                            HStack(spacing: 6) {
                                Rectangle()
                                    .fill(Theme.textMuted.opacity(0.3))
                                    .frame(width: 2, height: 14)
                                    .padding(.leading, 13)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .nightCard()
        .task(id: "\(store.ballparksRemaining.count)-\(location.hasUserLocation)") {
            await buildTrip()
        }
        .onAppear { location.requestLocationIfNeeded() }
    }

    private var proTag: some View {
        Text("PRO")
            .font(.caps(9, weight: .heavy))
            .tracking(2)
            .foregroundStyle(Theme.lights)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.lights.opacity(0.16)))
    }

    private var tripSummary: String {
        guard let first = stops.first, let last = stops.last else { return "" }
        let parks = stops.count
        if Calendar.current.isDate(first.game.date, inSameDayAs: last.game.date) {
            return "\(parks) parks, one big day:"
        }
        let start = first.game.date.formatted(.dateTime.month(.abbreviated).day())
        let end = last.game.date.formatted(.dateTime.month(.abbreviated).day())
        return "\(parks) new parks in one trip — \(start) to \(end):"
    }

    /// Miles for the leg ending at `index`: anchor → first stop, then park → park.
    private func legMiles(to index: Int) -> Int {
        let dest = stops[index].park
        let destLocation = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let originLocation: CLLocation
        if index == 0 {
            originLocation = anchor
        } else {
            let prev = stops[index - 1].park
            originLocation = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        }
        return Int((originLocation.distance(from: destLocation) / 1609.34).rounded())
    }

    /// Fetch schedules for the nearest unvisited parks and find the best
    /// small window where 2–3 of them have home games close together.
    private func buildTrip() async {
        isLoading = true
        defer { isLoading = false }

        let candidates = store.nearestUnvisitedParks(limit: 4, from: location.lastLocation)
        guard candidates.count >= 2 else {
            stops = []
            return
        }

        var parkGames: [(park: Ballpark, games: [MLBUpcomingGame])] = []
        for park in candidates {
            if Task.isCancelled { return }
            let games = await MLBStatsService.shared.upcomingHomeGames(
                teamMlbId: park.team.mlbId, days: 60, limit: 12
            )
            if !games.isEmpty { parkGames.append((park, games)) }
        }

        guard !Task.isCancelled else { return }
        stops = Self.bestTrip(from: parkGames)
    }

    /// Finds the earliest window of up to 4 days that covers home games at the
    /// most distinct parks (minimum 2). One game per park, ordered by date,
    /// capped at 3 stops.
    static func bestTrip(from parkGames: [(park: Ballpark, games: [MLBUpcomingGame])]) -> [RoadTripStop] {
        let all: [RoadTripStop] = parkGames
            .flatMap { pair in pair.games.map { RoadTripStop(park: pair.park, game: $0) } }
            .sorted { $0.game.date < $1.game.date }
        guard all.count >= 2 else { return [] }

        let windowSeconds: TimeInterval = 4 * 86400
        var best: [RoadTripStop] = []

        for start in all {
            let windowEnd = start.game.date.addingTimeInterval(windowSeconds)
            var perPark: [String: RoadTripStop] = [:]
            for stop in all where stop.game.date >= start.game.date && stop.game.date <= windowEnd {
                if perPark[stop.park.id] == nil { perPark[stop.park.id] = stop }
            }
            guard perPark.count >= 2 else { continue }
            // Order by date, then drop stops the fan can't physically reach:
            // require enough gap between consecutive first pitches to drive
            // the leg (~1 hour per 60 miles, plus the ~4h game itself).
            let ordered = perPark.values.sorted { $0.game.date < $1.game.date }
            var route: [RoadTripStop] = []
            for stop in ordered {
                guard route.count < 3 else { break }
                if let previous = route.last {
                    let miles = CLLocation(latitude: previous.park.latitude, longitude: previous.park.longitude)
                        .distance(from: CLLocation(latitude: stop.park.latitude, longitude: stop.park.longitude)) / 1609.34
                    let neededGap = (4 * 3600) + (miles / 60.0) * 3600
                    guard stop.game.date.timeIntervalSince(previous.game.date) >= neededGap else { continue }
                }
                route.append(stop)
            }
            guard route.count >= 2 else { continue }
            // Prefer more parks; on ties keep the earliest (we iterate in date order).
            if route.count > best.count {
                best = route
                if best.count == 3 { break }
            }
        }
        return best
    }
}

/// One stop on the suggested route: numbered pin, park, matchup, date, leg miles.
struct RoadTripStop: Identifiable {
    let park: Ballpark
    let game: MLBUpcomingGame
    var id: String { "\(park.id)-\(game.gamePk)" }
}

private struct RoadTripStopRow: View {
    let stop: RoadTripStop
    let index: Int
    let legMiles: Int

    private var opponent: Team? { Team.by(mlbId: stop.game.opponentMlbId) }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.stat(13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(stop.park.team.primary))
                .overlay(Circle().strokeBorder(stop.park.team.accentOnDark.opacity(0.6), lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(stop.park.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("vs \(opponent?.name ?? "TBD") · \(stop.game.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(stop.game.date.formatted(date: .omitted, time: .shortened))
                    .font(.stat(12, weight: .heavy))
                    .foregroundStyle(Theme.lights)
                Text("+\(legMiles) mi")
                    .font(.stat(11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stop \(index): \(stop.park.name), versus \(opponent?.name ?? "opponent to be determined"), \(stop.game.date.formatted(date: .abbreviated, time: .shortened)), \(legMiles) miles from the previous stop")
    }
}
