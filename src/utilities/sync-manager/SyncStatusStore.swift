import Foundation

/// Device-local sync-cycle status for throttle + Settings (#32).
///
/// **Why here (UserDefaults), not a third conceptual home:**
/// - `SyncLastPullMarker` is the cloud `synced_at` high-water for *incremental
///   pull* — not a wall-clock "last cycle finished" and not push outcome.
/// - `MemberState` / `UserIdentityModel` is syncable domain settings (staleness).
///   Cycle UI status must not ride that row to the cloud.
/// Same home family as `SyncLastPullMarker` / `MemberConnectionStore`:
/// per-member operational keys in UserDefaults.
enum SyncStatusStore {
    /// Foreground cycles only fire when this long has passed since last success.
    static let foregroundThrottleInterval: TimeInterval = 6 * 60 * 60

    static var userDefaults: UserDefaults = .standard

    private static let successPrefix = "syncLastSuccessfulCycleAt."
    private static let failureAtPrefix = "syncLastUnrecoveredFailureAt."
    private static let failureMessagePrefix = "syncLastUnrecoveredFailureMessage."

    static func lastSuccessfulCycleAt(
        memberId: UUID,
        defaults: UserDefaults = userDefaults
    ) -> Date? {
        defaults.object(forKey: successKey(for: memberId)) as? Date
    }

    /// Non-nil only while the last cycle failed and nothing has succeeded since.
    static func unrecoveredFailureMessage(
        memberId: UUID,
        defaults: UserDefaults = userDefaults
    ) -> String? {
        defaults.string(forKey: failureMessageKey(for: memberId))
    }

    static func unrecoveredFailureAt(
        memberId: UUID,
        defaults: UserDefaults = userDefaults
    ) -> Date? {
        defaults.object(forKey: failureAtKey(for: memberId)) as? Date
    }

    static func recordSuccess(
        memberId: UUID,
        at date: Date = Date(),
        defaults: UserDefaults = userDefaults
    ) {
        defaults.set(date, forKey: successKey(for: memberId))
        defaults.removeObject(forKey: failureAtKey(for: memberId))
        defaults.removeObject(forKey: failureMessageKey(for: memberId))
    }

    static func recordFailure(
        memberId: UUID,
        message: String,
        at date: Date = Date(),
        defaults: UserDefaults = userDefaults
    ) {
        defaults.set(date, forKey: failureAtKey(for: memberId))
        defaults.set(message, forKey: failureMessageKey(for: memberId))
    }

    static func clear(memberId: UUID, defaults: UserDefaults = userDefaults) {
        defaults.removeObject(forKey: successKey(for: memberId))
        defaults.removeObject(forKey: failureAtKey(for: memberId))
        defaults.removeObject(forKey: failureMessageKey(for: memberId))
    }

    /// Foreground trigger: run only if never succeeded, or success is older than throttle.
    static func shouldRunForegroundSync(
        memberId: UUID,
        now: Date = Date(),
        defaults: UserDefaults = userDefaults
    ) -> Bool {
        guard let last = lastSuccessfulCycleAt(memberId: memberId, defaults: defaults) else {
            return true
        }
        return now.timeIntervalSince(last) >= foregroundThrottleInterval
    }

    private static func successKey(for memberId: UUID) -> String {
        successPrefix + memberId.uuidString
    }

    private static func failureAtKey(for memberId: UUID) -> String {
        failureAtPrefix + memberId.uuidString
    }

    private static func failureMessageKey(for memberId: UUID) -> String {
        failureMessagePrefix + memberId.uuidString
    }
}
