import Foundation
import SwiftData

/// Whether this device has training data under the anonymous local member id.
enum LocalMemberHistoryProbe {
    static func hasLocalHistory(
        memberId: UUID,
        in context: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws -> Bool {
        let sessions = try performanceDataAccess.fetchSessions(memberId: memberId)
            .filter { $0.deletedAt == nil }
        if !sessions.isEmpty { return true }

        let pbDescriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == memberId }
        )
        let pbs = try context.fetch(pbDescriptor).filter { $0.deletedAt == nil }
        if !pbs.isEmpty { return true }

        let resetDescriptor = FetchDescriptor<ExerciseResetModel>(
            predicate: #Predicate { $0.memberId == memberId }
        )
        let resets = try context.fetch(resetDescriptor).filter { $0.deletedAt == nil }
        return !resets.isEmpty
    }
}
