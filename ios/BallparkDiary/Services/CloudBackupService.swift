import Foundation
import Observation

/// iCloud backup for the diary (Pro perk). Uses the iCloud key-value store —
/// no account, no server, just the user's own iCloud. The diary JSON is stored
/// under a single key with a timestamp, refreshed automatically on every save
/// while backup is enabled.
///
/// The KV store has a hard 1 MB quota, so backups are guarded by size: a diary
/// too large for the quota surfaces a clear message telling the user to use
/// manual export instead of silently failing.
@Observable
@MainActor
final class CloudBackupService {
    static let shared = CloudBackupService()

    /// Whether automatic iCloud backup is on. Toggled from Profile (Pro only).
    private(set) var isEnabled: Bool
    /// When the last successful backup was written.
    private(set) var lastBackupAt: Date?
    /// Human-readable problem from the last backup attempt, if any.
    private(set) var lastError: String?

    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private static let enabledKey = "ballparkdiary.icloudBackupEnabled"
    private static let dataKey = "ballparkdiary.backup.v1"
    private static let dateKey = "ballparkdiary.backup.date.v1"
    /// KV store total quota is 1 MB — leave headroom for the date key.
    private static let maxBackupBytes = 900_000

    private init() {
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        kv.synchronize()
        if let stamp = kv.object(forKey: Self.dateKey) as? Date {
            lastBackupAt = stamp
        }
    }

    /// Turn automatic backup on/off. Callers gate this behind Pro.
    func setEnabled(_ enabled: Bool, currentData: Data?) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        lastError = nil
        if enabled, let currentData {
            backup(currentData)
        }
    }

    /// Write a backup now. Called automatically from DiaryStore.save() while
    /// enabled, and manually from the Profile "Back Up Now" button.
    @discardableResult
    func backup(_ data: Data) -> Bool {
        guard data.count <= Self.maxBackupBytes else {
            lastError = "Your diary is too large for iCloud key-value backup. Use Export to save a full backup file."
            return false
        }
        kv.set(data, forKey: Self.dataKey)
        let now = Date.now
        kv.set(now, forKey: Self.dateKey)
        let synced = kv.synchronize()
        if synced {
            lastBackupAt = now
            lastError = nil
        } else {
            lastError = "iCloud isn't available right now. Check that you're signed into iCloud in Settings."
        }
        return synced
    }

    /// Read the most recent backup from iCloud, if one exists.
    func restoreData() -> Data? {
        kv.synchronize()
        return kv.data(forKey: Self.dataKey)
    }

    /// Date of the backup currently stored in iCloud (may come from another device).
    var storedBackupDate: Date? {
        kv.synchronize()
        return kv.object(forKey: Self.dateKey) as? Date ?? lastBackupAt
    }
}
