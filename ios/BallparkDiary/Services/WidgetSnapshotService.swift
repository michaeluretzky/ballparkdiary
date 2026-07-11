import Foundation
import WidgetKit

/// Snapshot of diary stats shared with the home-screen widget via the App
/// Group. Written on every diary save and whenever Pro status changes.
/// The widget target keeps a mirrored copy of this Codable shape.
struct WidgetSnapshot: Codable {
    var totalGames: Int
    var parksVisited: Int
    var seasonYear: Int
    var seasonGames: Int
    var seasonWins: Int
    var seasonLosses: Int
    var favoriteTeamAbbreviation: String
    var nextGameDate: Date?
    var nextGameMatchup: String?
    var nextGameBallpark: String?
    var updatedAt: Date
}

/// Writes widget data into the shared App Group and pokes WidgetKit.
enum WidgetSnapshotService {
    static let appGroupId = "group.app.rork.w8eewhvpa28g5c9ao7fpw"
    static let snapshotKey = "ballparkdiary.widget.snapshot"
    static let proKey = "ballparkdiary.widget.isPro"

    /// Publish the latest stats snapshot for the widget.
    @MainActor
    static func update(from store: DiaryStore) {
        guard let shared = UserDefaults(suiteName: appGroupId) else { return }
        let year = Calendar.current.component(.year, from: .now)
        let seasonGames = store.completedGames.filter {
            Calendar.current.component(.year, from: $0.date) == year
        }
        let seasonRooted = seasonGames.filter { $0.userRootedForHome != nil }
        let seasonWins = seasonRooted.filter(\.userWon).count
        let next = store.upcomingGames.first

        let snapshot = WidgetSnapshot(
            totalGames: store.totalGames,
            parksVisited: store.ballparkCount,
            seasonYear: year,
            seasonGames: seasonGames.count,
            seasonWins: seasonWins,
            seasonLosses: seasonRooted.count - seasonWins,
            favoriteTeamAbbreviation: store.favoriteTeam.abbreviation,
            nextGameDate: next?.date,
            nextGameMatchup: next.map { "\($0.awayTeam.abbreviation) @ \($0.homeTeam.abbreviation)" },
            nextGameBallpark: next?.ballpark.name,
            updatedAt: .now
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            shared.set(data, forKey: snapshotKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Publish the Pro entitlement so the widget can gate its content.
    static func setPro(_ isPro: Bool) {
        guard let shared = UserDefaults(suiteName: appGroupId) else { return }
        let previous = shared.object(forKey: proKey) as? Bool
        shared.set(isPro, forKey: proKey)
        if previous != isPro {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
