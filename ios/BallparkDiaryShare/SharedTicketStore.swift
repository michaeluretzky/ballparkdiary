import Foundation

/// A ticket the user shared into the app (via the Share Extension) that hasn't
/// been imported into the diary yet. The extension only extracts plain text
/// from the shared item (screenshot OCR, PDF text, or forwarded email body);
/// the main app does the MLB matchup detection + schedule confirmation.
nonisolated struct SharedTicketPayload: Codable, Sendable, Hashable {
    let id: String
    let text: String
    let sourceHint: String
    let receivedAt: Date
}

/// App Group-backed queue shared between the main app and the Share Extension.
/// The extension appends payloads; the app drains them on next launch/foreground.
nonisolated enum SharedTicketStore {
    static let appGroup = "group.app.rork.w8eewhvpa28g5c9ao7fpw"
    private static let key = "ballparkdiary.sharedTickets.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// Append a newly shared ticket to the queue.
    static func append(_ payload: SharedTicketPayload) {
        guard let defaults else { return }
        var current = load()
        current.append(payload)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: key)
        }
    }

    /// All pending shared tickets, oldest first.
    static func load() -> [SharedTicketPayload] {
        guard
            let defaults,
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([SharedTicketPayload].self, from: data)
        else { return [] }
        return decoded
    }

    /// Remove the given ids from the queue once they've been imported.
    static func remove(ids: Set<String>) {
        guard let defaults, !ids.isEmpty else { return }
        let remaining = load().filter { !ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: key)
        }
    }
}
