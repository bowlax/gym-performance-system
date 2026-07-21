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
    func includesUndatedManualPBsForEditDelete() {
        let squat = exercise(named: "Free Squat")
        let undated = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            weight: 120,
            reps: 5,
            achievedAt: nil,
            entryType: .manualEntry
        )

        let entries = ProgressionEntryMerger.merge(
            sessionHistory: [],
            personalBests: [undated],
            exercise: squat,
            from: .distantPast
        )

        #expect(entries.count == 1)
        #expect(entries.first?.personalBestId == undated.id)
        #expect(entries.first?.isUndated == true)
        #expect(entries.first?.formattedValue == "120kg × 5")
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
        #expect(entries.first?.setId == set.id)
    }

    @Test
    func deletingCurrentSessionPBPreservesRemainingMergedHistory() throws {
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
        let squat = exercise(named: "Free Squat")
        let calendar = Calendar.current
        let earlier = calendar.date(byAdding: .day, value: -10, to: Date())!
        let later = calendar.date(byAdding: .day, value: -5, to: Date())!

        let s1 = SessionModel(memberId: memberId, date: earlier)
        let e1 = ExerciseEntryModel(sessionId: s1.id, exerciseId: squat.id)
        let set1 = ModelSet(exerciseEntryId: e1.id, weight: 80, reps: 5)
        _ = try memberPerformance.saveSession(s1, entries: [e1], sets: [e1.id: [set1]])

        let s2 = SessionModel(memberId: memberId, date: later)
        let e2 = ExerciseEntryModel(sessionId: s2.id, exerciseId: squat.id)
        let set2 = ModelSet(exerciseEntryId: e2.id, weight: 100, reps: 5)
        _ = try memberPerformance.saveSession(s2, entries: [e2], sets: [e2.id: [set2]])

        func merged() throws -> [ProgressionEntry] {
            let sessionHistory = try memberPerformance.exerciseHistory(
                memberId: memberId,
                exerciseId: squat.id,
                from: .distantPast
            )
            let personalBests = try performanceDataAccess.fetchAllPBs(
                memberId: memberId,
                exerciseId: squat.id
            )
            return ProgressionEntryMerger.merge(
                sessionHistory: sessionHistory,
                personalBests: personalBests,
                exercise: squat,
                from: .distantPast
            )
        }

        let before = try merged()
        #expect(before.count == 2)

        let entryToDelete = try #require(before.first { $0.setId == set2.id })
        try memberPerformance.deleteHistoryEntry(
            setId: entryToDelete.setId,
            personalBestId: entryToDelete.personalBestId,
            memberId: memberId,
            exerciseId: squat.id
        )

        let after = try merged()
        #expect(after.count == 1)
        #expect(after.first?.setId == set1.id)
    }

    @Test
    func deletingManualPBPreservesSessionHistory() throws {
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
        let squat = exercise(named: "Free Squat")

        let session = SessionModel(memberId: memberId, date: Date())
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: squat.id)
        let set = ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5)
        _ = try memberPerformance.saveSession(session, entries: [entry], sets: [entry.id: [set]])

        let manual = manualPB(exerciseId: squat.id, weight: 100, reps: 5, achievedAt: Date())
        try performanceDataAccess.savePersonalBest(manual)

        func merged() throws -> [ProgressionEntry] {
            let sessionHistory = try memberPerformance.exerciseHistory(
                memberId: memberId,
                exerciseId: squat.id,
                from: .distantPast
            )
            let personalBests = try performanceDataAccess.fetchAllPBs(
                memberId: memberId,
                exerciseId: squat.id
            )
            return ProgressionEntryMerger.merge(
                sessionHistory: sessionHistory,
                personalBests: personalBests,
                exercise: squat,
                from: .distantPast
            )
        }

        let before = try merged()
        #expect(before.count == 2)

        let manualEntry = try #require(before.first { $0.personalBestId == manual.id })
        try memberPerformance.deleteHistoryEntry(
            setId: manualEntry.setId,
            personalBestId: manualEntry.personalBestId,
            memberId: memberId,
            exerciseId: squat.id
        )

        let after = try merged()
        #expect(after.count == 1)
        #expect(after.first?.setId == set.id)
    }

    @Test
    func deletingBestSetRevealsWeakerSetInSameSession() throws {
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
        let squat = exercise(named: "Free Squat")

        let session = SessionModel(memberId: memberId, date: Date())
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: squat.id)
        let weakerSet = ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5)
        let bestSet = ModelSet(exerciseEntryId: entry.id, weight: 100, reps: 5)
        _ = try memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [weakerSet, bestSet]]
        )

        func merged() throws -> [ProgressionEntry] {
            let sessionHistory = try memberPerformance.exerciseHistory(
                memberId: memberId,
                exerciseId: squat.id,
                from: .distantPast
            )
            let personalBests = try performanceDataAccess.fetchAllPBs(
                memberId: memberId,
                exerciseId: squat.id
            )
            return ProgressionEntryMerger.merge(
                sessionHistory: sessionHistory,
                personalBests: personalBests,
                exercise: squat,
                from: .distantPast
            )
        }

        let before = try merged()
        #expect(before.count == 1)
        #expect(before.first?.setId == bestSet.id)

        let entryToDelete = try #require(before.first)
        try memberPerformance.deleteHistoryEntry(
            setId: entryToDelete.setId,
            personalBestId: entryToDelete.personalBestId,
            memberId: memberId,
            exerciseId: squat.id
        )

        let after = try merged()
        #expect(after.count == 1)
        #expect(after.first?.setId == weakerSet.id)
        #expect(after.first?.isPB == true)
    }

    @Test
    func mergeSurvivesDuplicatePBSetIds() {
        let squat = exercise(named: "Free Squat")
        let set = ModelSet(exerciseEntryId: UUID(), weight: 80, reps: 5)
        let older = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            setId: set.id,
            weight: 80,
            reps: 5,
            achievedAt: Date().addingTimeInterval(-86_400),
            entryType: .sessionDerived
        )
        let newer = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            setId: set.id,
            weight: 80,
            reps: 5,
            achievedAt: Date(),
            entryType: .sessionDerived
        )

        let entries = ProgressionEntryMerger.merge(
            sessionHistory: [
                ExerciseSetSummary(sessionDate: Date(), set: set, isPB: true)
            ],
            personalBests: [older, newer],
            exercise: squat,
            from: .distantPast
        )

        #expect(entries.count == 1)
        #expect(entries.first?.personalBestId == newer.id)
    }

    @Test
    func doesNotSurfaceSupersededWarmupSetAsSeparateHistoryRow() throws {
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
        let squat = exercise(named: "Free Squat")

        let session = SessionModel(memberId: memberId, date: Date())
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: squat.id)
        _ = try memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [
                entry.id: [
                    ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5),
                    ModelSet(exerciseEntryId: entry.id, weight: 100, reps: 5)
                ]
            ]
        )

        let sessionHistory = try memberPerformance.exerciseHistory(
            memberId: memberId,
            exerciseId: squat.id,
            from: .distantPast
        )
        let personalBests = try performanceDataAccess.fetchAllPBs(
            memberId: memberId,
            exerciseId: squat.id
        )
        let entries = ProgressionEntryMerger.merge(
            sessionHistory: sessionHistory,
            personalBests: personalBests,
            exercise: squat,
            from: .distantPast
        )

        #expect(entries.count == 1)
        #expect(entries.first?.formattedValue == "100kg × 5")
    }
}
#endif
