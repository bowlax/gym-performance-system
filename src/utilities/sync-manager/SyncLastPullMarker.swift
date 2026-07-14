import Foundation

/// Per-member high-water mark for pull: the maximum cloud `synced_at` applied on the last successful pull.
enum SyncLastPullMarker {
    private static let keyPrefix = "syncLastPullSyncedAt."

    static func lastPullSyncedAt(memberId: UUID, defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: key(for: memberId)) as? Date
    }

    static func setLastPullSyncedAt(_ date: Date, memberId: UUID, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: key(for: memberId))
    }

    static func clear(memberId: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: memberId))
    }

    private static func key(for memberId: UUID) -> String {
        keyPrefix + memberId.uuidString
    }
}
