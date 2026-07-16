import Foundation
import SwiftData

/// Local member **state** (settings that sync), distinct from **identity** (`AccessControl`).
///
/// Identity (UUID, display name) lives in UserDefaults via AccessControl (#16).
/// Staleness and other syncable member settings live on the SwiftData
/// `UserIdentityModel` row keyed by that UUID. This type is the only product-
/// facing bridge across that split — derivation and UI must resolve staleness
/// here, not via AccessControl and not by fetching `UserIdentityModel` ad hoc.
enum MemberState {

    /// Design defaults when no SwiftData row exists (staleness OFF). Matches
    /// cloud column defaults; anonymous installs behave as today.
    static let defaultStaleness = MemberStalenessSetting(
        enabled: false,
        periods: 2,
        unit: .quarter
    )

    /// Resolves the current member's staleness setting from the SwiftData row
    /// keyed on the UserDefaults member UUID. Missing row → `defaultStaleness`.
    static func stalenessSetting(
        in context: ModelContext,
        memberId: UUID = AccessControl.persistedMemberId()
    ) throws -> MemberStalenessSetting {
        guard let row = try fetchRow(memberId: memberId, in: context) else {
            return defaultStaleness
        }
        return MemberStalenessSetting(
            enabled: row.stalenessEnabled,
            periods: row.stalenessPeriods,
            unit: row.stalenessUnit
        )
    }

    /// Writes staleness locally, creating the SwiftData row if absent, and bumps
    /// `updatedAt` so dirty push picks it up. Does not create a cloud member —
    /// settings-only PATCH fails honestly with `memberIdentityNotEstablished`
    /// until the broker has create-or-adopted.
    @discardableResult
    static func updateStalenessSetting(
        _ setting: MemberStalenessSetting,
        in context: ModelContext,
        memberId: UUID = AccessControl.persistedMemberId(),
        at date: Date = Date()
    ) throws -> UserIdentityModel {
        let row: UserIdentityModel
        if let existing = try fetchRow(memberId: memberId, in: context) {
            row = existing
        } else {
            row = UserIdentityModel(
                id: memberId,
                role: .member,
                displayName: AccessControl.userDefaults.string(
                    forKey: AccessControl.memberDisplayNameKey
                ) ?? "Member",
                createdAt: date,
                stalenessEnabled: setting.enabled,
                stalenessPeriods: setting.periods,
                stalenessUnit: setting.unit,
                updatedAt: date,
                syncedAt: nil
            )
            context.insert(row)
        }

        row.stalenessEnabled = setting.enabled
        row.stalenessPeriods = setting.periods
        row.stalenessUnit = setting.unit
        row.updatedAt = date
        try context.save()
        return row
    }

    private static func fetchRow(
        memberId: UUID,
        in context: ModelContext
    ) throws -> UserIdentityModel? {
        let descriptor = FetchDescriptor<UserIdentityModel>(
            predicate: #Predicate { $0.id == memberId }
        )
        return try context.fetch(descriptor).first
    }
}

/// Syncable member staleness window (#28). Storage unit is `quarter` / `month`.
struct MemberStalenessSetting: Equatable, Sendable {
    var enabled: Bool
    var periods: Int
    var unit: StalenessPeriodUnit
}
