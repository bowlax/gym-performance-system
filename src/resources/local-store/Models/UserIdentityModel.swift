import Foundation
import SwiftData

@Model
final class UserIdentityModel {
    @Attribute(.unique) var id: UUID
    var role: Role
    var displayName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        displayName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.createdAt = createdAt
    }
}
