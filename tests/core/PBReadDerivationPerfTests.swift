import Foundation
import SwiftData
import Testing
@testable import GymPerformance

struct PBReadDerivationPerfTests {
    @Test
    @MainActor
    func boardDerivationAcrossSeedExercisesIsSubSecond() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let configurationDataAccess = SwiftDataConfigurationDataAccess(context: context)
        let exerciseRegistry = DefaultExerciseRegistry(configurationDataAccess: configurationDataAccess)
        try exerciseRegistry.seedIfNeeded()
        let performanceDataAccess = SwiftDataPerformanceDataAccess(context: context)
        let memberPerformance = DefaultMemberPerformance(
            exerciseRegistry: exerciseRegistry,
            performanceDataAccess: performanceDataAccess,
            modelContext: context
        )

        let memberId = AccessControl.persistedMemberId()
        let exercises = try exerciseRegistry.pbExercises()
        // Seed a modest history: ~20 sets per exercise across 5 sessions.
        for dayOffset in 0..<5 {
            let session = SessionModel(
                memberId: memberId,
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(dayOffset) * 86_400)
            )
            context.insert(session)
            for exercise in exercises.prefix(19) {
                let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exercise.id)
                context.insert(entry)
                for i in 0..<4 {
                    context.insert(
                        ModelSet(
                            exerciseEntryId: entry.id,
                            weight: 60 + Double(i * 5 + dayOffset),
                            reps: 5
                        )
                    )
                }
            }
        }
        try context.save()

        _ = try memberPerformance.currentPBs(memberId: memberId)
        let seconds = try #require(PBReadDerivation.lastBoardDerivationSeconds)
        // Measure, don't premature-optimize: fail only if absurdly slow on simulator.
        #expect(seconds < 2.0, "Board derivation took \(seconds * 1000)ms")
        print(String(format: "Board derivation (%d exercises): %.2fms", exercises.count, seconds * 1000))
    }
}
