import Foundation

enum AccessControl {

    /// Phase 1 stub — returns a hardcoded member identity for single-user local use.
    static func currentUser() -> UserIdentityModel {
        UserIdentityModel(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            role: .member,
            displayName: "Member"
        )
    }
}
