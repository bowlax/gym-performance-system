import Foundation

/// Stable per-install device id used for `source_device_id` on cloud rows.
enum SyncDeviceIdentity {
    private static let userDefaultsKey = "syncDeviceUUID"

    static func persistedDeviceId(defaults: UserDefaults = .standard) -> UUID {
        if let existing = defaults.string(forKey: userDefaultsKey),
           let uuid = UUID(uuidString: existing) {
            return uuid
        }

        let created = UUID()
        defaults.set(created.uuidString, forKey: userDefaultsKey)
        return created
    }
}
