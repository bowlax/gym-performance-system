import Foundation

enum AccessControl {

    static let legacyMemberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    static let memberUUIDKey = "memberUUID"
    static let memberDisplayNameKey = "memberDisplayName"

    /// UserDefaults backing store. Override in tests for isolation.
    static var userDefaults: UserDefaults = .standard

    /// Returns the persisted member UUID, generating and storing one on first access.
    static func persistedMemberId() -> UUID {
        if let stored = userDefaults.string(forKey: memberUUIDKey),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }

        let newId = UUID()
        userDefaults.set(newId.uuidString, forKey: memberUUIDKey)
        if userDefaults.string(forKey: memberDisplayNameKey) == nil {
            userDefaults.set("Member", forKey: memberDisplayNameKey)
        }
        return newId
    }

    static func currentUser() -> UserIdentityModel {
        UserIdentityModel(
            id: persistedMemberId(),
            role: .member,
            displayName: userDefaults.string(forKey: memberDisplayNameKey) ?? "Member"
        )
    }
}
