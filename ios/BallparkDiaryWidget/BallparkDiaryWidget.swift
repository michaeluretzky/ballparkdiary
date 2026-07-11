import WidgetKit
import SwiftUI

// MARK: - Shared snapshot (mirrors WidgetSnapshotService in the app target)

nonisolated struct WidgetSnapshot: Codable {
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

nonisolated enum SharedStore {
    static let appGroupId = "group.app.rork.w8eewhvpa28g5c9ao7fpw"
    static let snapshotKey = "ballparkdiary.widget.snapshot"
    static let proKey = "ballparkdiary.widget.isPro"

    static func load() -> (snapshot: WidgetSnapshot?, isPro: Bool) {
        guard let shared = UserDefaults(suiteName: appGroupId) else { return (nil, false) }
        let isPro = shared.bool(forKey: proKey)
        guard let data = shared.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return (nil, isPro)
        }
        return (snapshot, isPro)
    }
}

// MARK: - Timeline

nonisolated struct DiaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let isPro: Bool

    static var placeholder: DiaryEntry {
        DiaryEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                totalGames: 24, parksVisited: 7,
                seasonYear: Calendar.current.component(.year, from: .now),
                seasonGames: 6, seasonWins: 4, seasonLosses: 2,
                favoriteTeamAbbreviation: "NYY",
                nextGameDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
                nextGameMatchup: "BOS @ NYY",
                nextGameBallpark: "Yankee Stadium",
                updatedAt: .now
            ),
            isPro: true
        )
    }
}

nonisolated struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DiaryEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DiaryEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        let (snapshot, isPro) = SharedStore.load()
        completion(DiaryEntry(date: .now, snapshot: snapshot, isPro: isPro))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiaryEntry>) -> Void) {
        let (snapshot, isPro) = SharedStore.load()
        let entry = DiaryEntry(date: .now, snapshot: snapshot, isPro: isPro)
        // Refresh every 30 minutes so the next-game countdown stays fresh.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Palette (mirrors the app's stadium-night theme)

nonisolated enum WidgetTheme {
    static let night = Color(red: 0.043, green: 0.082, blue: 0.188)
    static let nightDeep = Color(red: 0.024, green: 0.047, blue: 0.118)
    static let clay = Color(red: 0.878, green: 0.478, blue: 0.169)
    static let grass = Color(red: 0.290, green: 0.486, blue: 0.227)
    static let lights = Color(red: 0.961, green: 0.784, blue: 0.259)
    static let foul = Color(red: 0.870, green: 0.240, blue: 0.240)
    static let textSecondary = Color(red: 0.647, green: 0.690, blue: 0.788)
    static let textMuted = Color(red: 0.439, green: 0.490, blue: 0.604)

    static var background: LinearGradient {
        LinearGradient(colors: [nightDeep, night], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Views

struct WidgetView: View {
    var entry: DiaryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.isPro {
                LockedWidgetView()
            } else if let snapshot = entry.snapshot {
                switch family {
                case .systemMedium, .systemLarge:
                    MediumDiaryView(snapshot: snapshot)
                default:
                    SmallDiaryView(snapshot: snapshot)
                }
            } else {
                EmptyDiaryWidgetView()
            }
        }
        .containerBackground(for: .widget) { WidgetTheme.background }
    }
}

/// Free users see a branded lock — the widget itself is a Pro perk.
private struct LockedWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WidgetTheme.lights)
            Text("Ballpark Diary")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
            Text("Unlock the widget with Pro")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyDiaryWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "baseball.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WidgetTheme.clay)
            Text("Open the app to log your first game")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}

/// Small: season record + games count.
private struct SmallDiaryView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetTheme.clay)
                Text("\(String(snapshot.seasonYear)) SEASON")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(WidgetTheme.textMuted)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 2)

            Text("\(snapshot.seasonGames)")
                .font(.system(size: 34, weight: .black).monospacedDigit())
                .foregroundStyle(.white)
            Text(snapshot.seasonGames == 1 ? "game this season" : "games this season")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)

            Spacer(minLength: 2)

            HStack(spacing: 6) {
                if snapshot.seasonWins + snapshot.seasonLosses > 0 {
                    Text("\(snapshot.seasonWins)–\(snapshot.seasonLosses)")
                        .font(.system(size: 13, weight: .heavy).monospacedDigit())
                        .foregroundStyle(snapshot.seasonWins >= snapshot.seasonLosses ? WidgetTheme.grass : WidgetTheme.foul)
                }
                Spacer(minLength: 0)
                Text(snapshot.favoriteTeamAbbreviation)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(WidgetTheme.lights)
            }
        }
        .padding(2)
    }
}

/// Medium: next game countdown when one exists, otherwise lifetime summary.
private struct MediumDiaryView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(snapshot.seasonYear)) SEASON")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(WidgetTheme.textMuted)
                Text("\(snapshot.seasonGames)")
                    .font(.system(size: 32, weight: .black).monospacedDigit())
                    .foregroundStyle(.white)
                Text("games")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                if snapshot.seasonWins + snapshot.seasonLosses > 0 {
                    Text("\(snapshot.seasonWins)–\(snapshot.seasonLosses) record")
                        .font(.system(size: 11, weight: .heavy).monospacedDigit())
                        .foregroundStyle(snapshot.seasonWins >= snapshot.seasonLosses ? WidgetTheme.grass : WidgetTheme.foul)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 4) {
                if let date = snapshot.nextGameDate, date > .now, let matchup = snapshot.nextGameMatchup {
                    Text("NEXT GAME")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(WidgetTheme.lights)
                    Text(matchup)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let ballpark = snapshot.nextGameBallpark {
                        Text(ballpark)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WidgetTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Text(date, style: .relative)
                        .font(.system(size: 11, weight: .heavy).monospacedDigit())
                        .foregroundStyle(WidgetTheme.clay)
                        .lineLimit(1)
                } else {
                    Text("LIFETIME")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(WidgetTheme.lights)
                    Text("\(snapshot.totalGames) games")
                        .font(.system(size: 16, weight: .black).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("\(snapshot.parksVisited)/30 ballparks")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.textSecondary)
                    Text(snapshot.favoriteTeamAbbreviation)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(WidgetTheme.lights)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(2)
    }
}

// MARK: - Widget configuration

struct BallparkDiaryWidget: Widget {
    let kind: String = "BallparkDiaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Ballpark Diary")
        .description("Your season at a glance — games, record, and the countdown to your next ticket.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
