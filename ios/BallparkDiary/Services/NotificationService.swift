import Foundation
import Observation
import UserNotifications

/// Local game-day reminders for upcoming (On Deck) games. Free feature.
/// When enabled, schedules one notification per upcoming game — the morning
/// of the game, or two hours before an early first pitch. Uses local
/// notifications only; nothing leaves the device.
@Observable
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// Whether the user has turned reminders on (and permission was granted).
    private(set) var isEnabled: Bool
    /// True when the user tried to enable reminders but iOS permission is denied.
    private(set) var permissionDenied: Bool = false

    private static let enabledKey = "ballparkdiary.gameDayReminders"
    private static let identifierPrefix = "gameday-"
    /// iOS caps pending local notifications at 64 — stay well under it.
    private static let maxScheduled = 20

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Toggle reminders. Enabling requests notification permission first;
    /// if denied, `permissionDenied` flips so the UI can point to Settings.
    func setEnabled(_ enabled: Bool, upcoming: [AttendedGame]) async {
        if enabled {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .denied:
                permissionDenied = true
                isEnabled = false
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                permissionDenied = !granted
                isEnabled = granted
            default:
                permissionDenied = false
                isEnabled = true
            }
        } else {
            isEnabled = false
        }
        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        await sync(upcoming: upcoming)
    }

    /// Re-sync scheduled reminders after the diary changes. No-op when off.
    func syncIfEnabled(upcoming: [AttendedGame]) {
        guard isEnabled else { return }
        Task { await sync(upcoming: upcoming) }
    }

    /// Re-read the iOS permission state so a stale "denied" warning clears
    /// after the user grants notifications in Settings and returns.
    func refreshPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionDenied = isEnabled == false && permissionDenied
            && settings.authorizationStatus == .denied
    }

    /// Replace all of our pending reminders with one per upcoming game.
    private func sync(upcoming: [AttendedGame]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        guard isEnabled else { return }

        let calendar = Calendar.current
        for game in upcoming.sorted(by: { $0.date < $1.date }).prefix(Self.maxScheduled) {
            guard game.date > .now else { continue }

            // Morning-of at 9:00; for early first pitches (or when 9 AM has
            // already passed today) fall back to two hours before the game.
            var fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: game.date) ?? game.date
            if fireDate >= game.date || fireDate <= .now {
                fireDate = game.date.addingTimeInterval(-2 * 3600)
            }
            guard fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Game day at \(game.ballpark.name)"
            let time = game.date.formatted(date: .omitted, time: .shortened)
            var body = "\(game.awayTeam.fullName) at \(game.homeTeam.fullName) — first pitch at \(time)."
            let section = game.section.trimmingCharacters(in: .whitespaces)
            if !section.isEmpty {
                body += " Section \(section) awaits."
            }
            content.body = body
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + game.id.uuidString,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
