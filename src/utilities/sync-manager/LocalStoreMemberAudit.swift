import Foundation
import SwiftData

#if DEBUG
/// One-shot operator audit: rows per table grouped by effective member id.
/// Logs to Xcode console on launch when wired from `AppDependencies`.
enum LocalStoreMemberAudit {
    struct MemberCounts: Sendable {
        var sessions = 0
        var sessionsDirty = 0
        var exerciseEntries = 0
        var exerciseEntriesDirty = 0
        var sets = 0
        var setsDirty = 0
        var personalBests = 0
        var personalBestsDirty = 0
        var personalBestsManual = 0
        var personalBestsSessionDerived = 0
        var exerciseResets = 0
        var exerciseResetsDirty = 0
        var userIdentities = 0

        var trainingTotal: Int {
            sessions + exerciseEntries + sets + personalBests + exerciseResets
        }
    }

    @MainActor
    static func logGroupedCounts(in context: ModelContext) {
        do {
            try emitReport(in: context)
        } catch {
            print("LocalStoreMemberAudit ERROR: \(error)")
        }
    }

    @MainActor
    private static func emitReport(in context: ModelContext) throws {
        var byMember: [UUID: MemberCounts] = [:]

        func bucket(_ memberId: UUID) -> MemberCounts {
            if byMember[memberId] == nil {
                byMember[memberId] = MemberCounts()
            }
            return byMember[memberId]!
        }

        let sessions = try context.fetch(FetchDescriptor<SessionModel>())
        var sessionOwner: [UUID: UUID] = [:]
        for session in sessions {
            sessionOwner[session.id] = session.memberId
            var counts = bucket(session.memberId)
            counts.sessions += 1
            if SyncDirtiness.isDirty(updatedAt: session.updatedAt, syncedAt: session.syncedAt) {
                counts.sessionsDirty += 1
            }
            byMember[session.memberId] = counts
        }

        for entry in try context.fetch(FetchDescriptor<ExerciseEntryModel>()) {
            guard let memberId = sessionOwner[entry.sessionId] else { continue }
            var counts = bucket(memberId)
            counts.exerciseEntries += 1
            if SyncDirtiness.isDirty(updatedAt: entry.updatedAt, syncedAt: entry.syncedAt) {
                counts.exerciseEntriesDirty += 1
            }
            byMember[memberId] = counts
        }

        for set in try context.fetch(FetchDescriptor<ModelSet>()) {
            guard let entry = try fetchEntry(id: set.exerciseEntryId, in: context),
                  let memberId = sessionOwner[entry.sessionId] else {
                continue
            }
            var counts = bucket(memberId)
            counts.sets += 1
            if SyncDirtiness.isDirty(updatedAt: set.updatedAt, syncedAt: set.syncedAt) {
                counts.setsDirty += 1
            }
            byMember[memberId] = counts
        }

        for pb in try context.fetch(FetchDescriptor<PersonalBestModel>()) {
            var counts = bucket(pb.memberId)
            counts.personalBests += 1
            if SyncDirtiness.isDirty(updatedAt: pb.effectiveUpdatedAt, syncedAt: pb.syncedAt) {
                counts.personalBestsDirty += 1
            }
            switch pb.entryType {
            case .manualEntry: counts.personalBestsManual += 1
            case .sessionDerived: counts.personalBestsSessionDerived += 1
            }
            byMember[pb.memberId] = counts
        }

        for reset in try context.fetch(FetchDescriptor<ExerciseResetModel>()) {
            var counts = bucket(reset.memberId)
            counts.exerciseResets += 1
            if SyncDirtiness.isDirty(updatedAt: reset.updatedAt, syncedAt: reset.syncedAt) {
                counts.exerciseResetsDirty += 1
            }
            byMember[reset.memberId] = counts
        }

        for identity in try context.fetch(FetchDescriptor<UserIdentityModel>()) {
            var counts = bucket(identity.id)
            counts.userIdentities += 1
            byMember[identity.id] = counts
        }

        let canonical = MemberConnectionStore.connectedMemberId
        let persisted = AccessControl.persistedMemberId()

        print("=== LocalStoreMemberAudit ===")
        print("AccessControl.persistedMemberId=\(persisted.uuidString)")
        print("MemberConnectionStore.connectedMemberId=\(canonical?.uuidString ?? "nil")")
        print("distinct memberIds=\(byMember.count)")

        for memberId in byMember.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let c = byMember[memberId]!
            print(
                """
                memberId=\(memberId.uuidString)
                  sessions=\(c.sessions) dirty=\(c.sessionsDirty)
                  exercise_entries=\(c.exerciseEntries) dirty=\(c.exerciseEntriesDirty)
                  sets=\(c.sets) dirty=\(c.setsDirty)
                  personal_bests=\(c.personalBests) dirty=\(c.personalBestsDirty) manual=\(c.personalBestsManual) sessionDerived=\(c.personalBestsSessionDerived)
                  exercise_resets=\(c.exerciseResets) dirty=\(c.exerciseResetsDirty)
                  user_identities=\(c.userIdentities)
                  training_total=\(c.trainingTotal)
                """
            )
        }
        print("=== /LocalStoreMemberAudit ===")
    }

    private static func fetchEntry(
        id: UUID,
        in context: ModelContext
    ) throws -> ExerciseEntryModel? {
        let descriptor = FetchDescriptor<ExerciseEntryModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }
}
#endif
