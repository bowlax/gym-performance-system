import Foundation
import SwiftData

enum MemberIdentityMigration {

    static let migrationCompleteKey = "memberIdMigrationComplete"

    static func runMigrationIfNeeded(
        context: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws {
        let defaults = AccessControl.userDefaults
        guard !defaults.bool(forKey: migrationCompleteKey) else { return }

        let newMemberId = AccessControl.persistedMemberId()
        let legacyId = AccessControl.legacyMemberId

        let sessions = try performanceDataAccess.fetchSessions(memberId: legacyId)
        for session in sessions {
            session.memberId = newMemberId
        }

        let pbDescriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == legacyId }
        )
        let personalBests = try context.fetch(pbDescriptor)
        for pb in personalBests {
            pb.memberId = newMemberId
        }

        try context.save()
        defaults.set(true, forKey: migrationCompleteKey)
    }
}
