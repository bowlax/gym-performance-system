#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct ProgressionEntryMergerTests {

    private let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    private func exercise(named name: String) -> ExerciseModel {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise: \(name)")
        }
        return exercise
    }

    private func manualPB(
        exerciseId: UUID,
        weight: Double,
        reps: Int,
        achievedAt: Date
    ) -> PersonalBestModel {
        PersonalBestModel(
            memberId: memberId,
            exerciseId: exerciseId,
            setId: nil,
            weight: weight,
            reps: reps,
            achievedAt: achievedAt,
            isCurrent: true,
            entryType: .manualEntry
        )
    }

    @Test
    func includesManualPBWhenNoSessionsExist() {
        let squat = exercise(named: "Free Squat")
        let manual = manualPB(
            exerciseId: squat.id,
            weight: 100,
            reps: 5,
            achievedAt: Date()
        )

        let entries = ProgressionEntryMerger.merge(
            sessionHistory: [],
            personalBests: [manual],
            exercise: squat,
            from: .distantPast
        )

        #expect(entries.count == 1)
        #expect(entries.first?.personalBestId == manual.id)
        #expect(entries.first?.isPB == true)
        #expect(entries.first?.formattedValue == "100kg × 5")
    }

    @Test
    func includesManualPBOnSameDayAsSession() {
        let squat = exercise(named: "Free Squat")
        let sessionDate = Date()
        let entryId = UUID()
        let set = ModelSet(exerciseEntryId: entryId, weight: 90, reps: 5)
        let manual = manualPB(
            exerciseId: squat.id,
            weight: 100,
            reps: 5,
            achievedAt: sessionDate
        )

        let entries = ProgressionEntryMerger.merge(
            sessionHistory: [
                ExerciseSetSummary(sessionDate: sessionDate, set: set, isPB: false)
            ],
            personalBests: [manual],
            exercise: squat,
            from: .distantPast
        )

        #expect(entries.count == 2)
        #expect(entries.contains { $0.personalBestId == manual.id })
        #expect(entries.contains { $0.id == set.id })
    }

    @Test
    func doesNotDuplicateSessionDerivedPBAlreadyInHistory() {
        let squat = exercise(named: "Free Squat")
        let sessionDate = Date()
        let entryId = UUID()
        let set = ModelSet(exerciseEntryId: entryId, weight: 100, reps: 5)
        let sessionPB = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            setId: set.id,
            weight: 100,
            reps: 5,
            achievedAt: sessionDate,
            isCurrent: true,
            entryType: .sessionDerived
        )

        let entries = ProgressionEntryMerger.merge(
            sessionHistory: [
                ExerciseSetSummary(sessionDate: sessionDate, set: set, isPB: true)
            ],
            personalBests: [sessionPB],
            exercise: squat,
            from: .distantPast
        )

        #expect(entries.count == 1)
        #expect(entries.first?.id == set.id)
        #expect(entries.first?.personalBestId == sessionPB.id)
    }
}
#endif
