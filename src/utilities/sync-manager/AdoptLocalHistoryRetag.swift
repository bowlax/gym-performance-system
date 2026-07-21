import Foundation
import SwiftData

/// Re-tags anonymous local training history onto the broker's canonical member id
/// before first-connect upload when adopt + proceedToUpload (#17 / #31).
///
/// Contrast `DiscardCloudWins` (#33): discard **clears** anonymous history and
/// deliberately does **not** copy anonymous staleness onto the adopted member.
/// Re-tag **keeps** local history and deliberately **does** migrate staleness —
/// both are product decisions, not accidents.
enum AdoptLocalHistoryRetag {
    static let pendingAdoptFromKey = "adoptLocalHistory.pendingFrom"
    static let pendingAdoptToKey = "adoptLocalHistory.pendingTo"

    static var userDefaults: UserDefaults = .standard

    /// Finish an interrupted adopt after SwiftData save succeeded but UserDefaults
    /// adopt did not run, or re-run retag if save never committed. Safe on launch
    /// and at connect start.
    @MainActor
    static func completePendingAdoptIfNeeded(
        in context: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws {
        guard let from = pendingAdoptFrom, let to = pendingAdoptTo else { return }

        if AccessControl.persistedMemberId() == to {
            clearPendingAdopt()
            return
        }

        if try LocalMemberHistoryProbe.hasLocalHistory(
            memberId: from,
            in: context,
            performanceDataAccess: performanceDataAccess
        ) {
            try retagAndAdopt(
                anonymousMemberId: from,
                canonicalMemberId: to,
                in: context,
                performanceDataAccess: performanceDataAccess
            )
            return
        }

        AccessControl.adoptCanonicalMemberId(to)
        clearAnonymousSyncMarkers(memberId: from)
        clearPendingAdopt()
    }

    /// Prior device member id to heal from when it differs from the connected canonical id.
    ///
    /// Keys only on explicit device-identity signals — never scans the store for arbitrary
    /// `memberId != canonical` rows (another member's rows must not be re-parented here).
    ///
    /// 1. Interrupted adopt marker (`pendingAdoptFrom` → `pendingAdoptTo == canonical`)
    /// 2. Else `AccessControl.persistedMemberId()` when still pre-adopt
    static func resolvePriorDeviceMemberId(canonicalMemberId: UUID) -> UUID? {
        if let from = pendingAdoptFrom, let to = pendingAdoptTo {
            guard to == canonicalMemberId, from != canonicalMemberId else { return nil }
            return from
        }
        let persisted = AccessControl.persistedMemberId()
        guard persisted != canonicalMemberId else { return nil }
        return persisted
    }

    /// Self-healing safety net before sync push (#17): re-tag stranded local rows keyed on
    /// the known prior device id onto the session canonical member id.
    ///
    /// Skipped when not connected, when JWT canonical ≠ stored connection, when cloud already
    /// has member history (discard-cloud-wins territory — #33), or when identity is aligned.
    @MainActor
    static func healStrandedLocalHistoryIfNeeded(
        canonicalMemberId: UUID,
        skipWhenCloudHasMemberHistory: Bool,
        in context: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws -> Bool {
        guard MemberConnectionStore.isConnected,
              MemberConnectionStore.hasUsableSession,
              MemberConnectionStore.connectedMemberId == canonicalMemberId else {
            return false
        }
        guard !skipWhenCloudHasMemberHistory else { return false }
        guard let priorId = resolvePriorDeviceMemberId(canonicalMemberId: canonicalMemberId),
              priorId != canonicalMemberId else {
            return false
        }

        if try LocalMemberHistoryProbe.hasLocalHistory(
            memberId: priorId,
            in: context,
            performanceDataAccess: performanceDataAccess
        ) {
            try retagAndAdopt(
                anonymousMemberId: priorId,
                canonicalMemberId: canonicalMemberId,
                in: context,
                performanceDataAccess: performanceDataAccess
            )
            return true
        }

        if AccessControl.persistedMemberId() == priorId {
            try completePendingAdoptIfNeeded(
                in: context,
                performanceDataAccess: performanceDataAccess
            )
            return AccessControl.persistedMemberId() == canonicalMemberId
        }
        return false
    }

    /// Idempotent: only rows still keyed on `anonymousMemberId` are retagged.
    @MainActor
    static func retagAndAdopt(
        anonymousMemberId: UUID,
        canonicalMemberId: UUID,
        in context: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws {
        guard anonymousMemberId != canonicalMemberId else { return }

        setPendingAdopt(from: anonymousMemberId, to: canonicalMemberId)
        try retagTrainingRows(
            anonymousMemberId: anonymousMemberId,
            canonicalMemberId: canonicalMemberId,
            in: context,
            performanceDataAccess: performanceDataAccess
        )
        try migrateUserIdentity(
            anonymousMemberId: anonymousMemberId,
            canonicalMemberId: canonicalMemberId,
            in: context
        )
        try context.save()
        AccessControl.adoptCanonicalMemberId(canonicalMemberId)
        clearPendingAdopt()
        clearAnonymousSyncMarkers(memberId: anonymousMemberId)
    }

    // MARK: - Retag

    private static func retagTrainingRows(
        anonymousMemberId: UUID,
        canonicalMemberId: UUID,
        in context: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws {
        for session in try performanceDataAccess.fetchSessions(memberId: anonymousMemberId) {
            session.memberId = canonicalMemberId
            session.syncedAt = nil
            for entry in try performanceDataAccess.fetchExerciseEntries(sessionId: session.id) {
                entry.syncedAt = nil
                for set in try performanceDataAccess.fetchSets(exerciseEntryId: entry.id) {
                    set.syncedAt = nil
                }
            }
        }

        let pbDescriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == anonymousMemberId }
        )
        for pb in try context.fetch(pbDescriptor) {
            pb.memberId = canonicalMemberId
            pb.syncedAt = nil
        }

        let resetDescriptor = FetchDescriptor<ExerciseResetModel>(
            predicate: #Predicate { $0.memberId == anonymousMemberId }
        )
        for reset in try context.fetch(resetDescriptor) {
            reset.memberId = canonicalMemberId
            reset.syncedAt = nil
        }
    }

    /// Re-tag path: migrate anonymous staleness onto the canonical identity row.
    ///
    /// #33 discard deliberately deletes the anonymous `UserIdentityModel` without
    /// copying settings — we cleared history and must not soft-merge preferences.
    /// Re-tag keeps history, so we keep this device's staleness preferences too.
    private static func migrateUserIdentity(
        anonymousMemberId: UUID,
        canonicalMemberId: UUID,
        in context: ModelContext
    ) throws {
        guard let anonymous = try fetchIdentity(id: anonymousMemberId, in: context) else {
            return
        }

        if let canonical = try fetchIdentity(id: canonicalMemberId, in: context) {
            canonical.stalenessEnabled = anonymous.stalenessEnabled
            canonical.stalenessPeriods = anonymous.stalenessPeriods
            canonical.stalenessUnit = anonymous.stalenessUnit
            canonical.updatedAt = Date()
            canonical.syncedAt = nil
            context.delete(anonymous)
        } else {
            let migrated = UserIdentityModel(
                id: canonicalMemberId,
                role: anonymous.role,
                displayName: anonymous.displayName,
                createdAt: anonymous.createdAt,
                stalenessEnabled: anonymous.stalenessEnabled,
                stalenessPeriods: anonymous.stalenessPeriods,
                stalenessUnit: anonymous.stalenessUnit,
                updatedAt: Date(),
                syncedAt: nil
            )
            context.insert(migrated)
            context.delete(anonymous)
        }
    }

    private static func fetchIdentity(
        id: UUID,
        in context: ModelContext
    ) throws -> UserIdentityModel? {
        let descriptor = FetchDescriptor<UserIdentityModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Pending adopt marker

    private static var pendingAdoptFrom: UUID? {
        userDefaults.string(forKey: pendingAdoptFromKey).flatMap(UUID.init(uuidString:))
    }

    private static var pendingAdoptTo: UUID? {
        userDefaults.string(forKey: pendingAdoptToKey).flatMap(UUID.init(uuidString:))
    }

    private static func setPendingAdopt(from: UUID, to: UUID) {
        userDefaults.set(from.uuidString, forKey: pendingAdoptFromKey)
        userDefaults.set(to.uuidString, forKey: pendingAdoptToKey)
    }

    private static func clearPendingAdopt() {
        userDefaults.removeObject(forKey: pendingAdoptFromKey)
        userDefaults.removeObject(forKey: pendingAdoptToKey)
    }

    private static func clearAnonymousSyncMarkers(memberId: UUID) {
        SyncLastPullMarker.clear(memberId: memberId)
        SyncStatusStore.clear(memberId: memberId)
    }
}
