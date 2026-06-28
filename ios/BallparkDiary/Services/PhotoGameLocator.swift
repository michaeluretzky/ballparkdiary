import Foundation
import CoreLocation

/// Identifies which ballpark a photo was taken at — and which game it captured —
/// using only the photo's embedded EXIF metadata (GPS coordinates + capture
/// date). No paid AI, no servers: the GPS pins the stadium, and the date is
/// matched against the free public MLB Stats API to recover the exact matchup.
nonisolated final class PhotoGameLocator: Sendable {
    static let shared = PhotoGameLocator()
    private init() {}

    /// Maximum distance (miles) from a ballpark for a photo to count as "at" it.
    /// Generous enough to cover the entire stadium footprint and its parking
    /// lots, tight enough that a photo from across town won't false-match.
    static let maxParkRadiusMiles: Double = 0.75

    /// The nearest ballpark to a coordinate, with the distance in miles.
    func nearestPark(to coordinate: CLLocationCoordinate2D) -> (park: Ballpark, miles: Double)? {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var best: (park: Ballpark, miles: Double)?
        for park in Ballpark.all {
            let meters = loc.distance(from: CLLocation(latitude: park.latitude, longitude: park.longitude))
            let miles = meters * 0.000621371
            if best == nil || miles < best!.miles {
                best = (park, miles)
            }
        }
        return best
    }

    /// Resolve the actual MLB game played at `ballpark` on (or adjacent to)
    /// `date`. Tries the exact calendar day first, then ±1 day to absorb any
    /// timezone drift between the photo's local clock and the league day.
    /// Venue-name matching makes this correct even for international venues
    /// (London Stadium, Tokyo Dome) whose home team isn't a fixed MLB club.
    func resolveGame(ballpark: Ballpark, around date: Date) async -> MLBGameResult? {
        let cal = Calendar(identifier: .gregorian)
        let candidates: [Date] = [
            date,
            cal.date(byAdding: .day, value: -1, to: date),
            cal.date(byAdding: .day, value: 1, to: date)
        ].compactMap { $0 }

        let teamMlbId = ballpark.team.mlbId
        let filter: Int? = teamMlbId > 0 ? teamMlbId : nil

        for day in candidates {
            guard
                let results = try? await MLBStatsService.shared.games(on: day, teamMlbId: filter),
                !results.isEmpty
            else { continue }

            // Strongest signal: the API venue name maps to this exact park.
            if let byVenue = results.first(where: { Ballpark.by(venueName: $0.venueName)?.id == ballpark.id }) {
                return byVenue
            }
            // Otherwise the home team's home game on that day.
            if teamMlbId > 0, let home = results.first(where: { $0.homeMlbId == teamMlbId }) {
                return home
            }
        }
        return nil
    }

    /// Convert a GPS compass heading (degrees) into a cardinal label.
    static func compassLabel(forHeading degrees: Double) -> String {
        let dirs = ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 22.5) / 45.0) % 8
        return dirs[(index + 8) % 8]
    }
}
