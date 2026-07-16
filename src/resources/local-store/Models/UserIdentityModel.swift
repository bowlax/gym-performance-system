import Foundation
import SwiftData

@Model
final class UserIdentityModel {
    @Attribute(.unique) var id: UUID
    var role: Role
    var displayName: String
    var createdAt: Date

    // MARK: Staleness (#28 STEP 2 — additive, defaulted for lightweight migration)

    /// When false, freshness never expires. Default off so anonymous / existing installs are unchanged.
    var stalenessEnabled: Bool = false
    /// Complete periods in the staleness window. Design default: two quarters.
    var stalenessPeriods: Int = 2
    /// Storage unit matching cloud (`quarter` | `month`).
    var stalenessUnitRaw: String = StalenessPeriodUnit.quarter.rawValue
    /// Device write time for LWW / dirty push of member settings.
    var updatedAt: Date = Date()
    /// Set when member settings have been successfully pushed.
    var syncedAt: Date?

    var stalenessUnit: StalenessPeriodUnit {
        get { StalenessPeriodUnit(rawValue: stalenessUnitRaw) ?? .quarter }
        set { stalenessUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        role: Role,
        displayName: String,
        createdAt: Date = Date(),
        stalenessEnabled: Bool = false,
        stalenessPeriods: Int = 2,
        stalenessUnit: StalenessPeriodUnit = .quarter,
        updatedAt: Date = Date(),
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.createdAt = createdAt
        self.stalenessEnabled = stalenessEnabled
        self.stalenessPeriods = stalenessPeriods
        self.stalenessUnitRaw = stalenessUnit.rawValue
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
    }
}
