#if canImport(Testing)
import Foundation
import Testing
import SwiftData
@testable import GymPerformance

@Suite
struct OnboardingPBSaverTests {

    private let testMemberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    private struct TestContext {
        let memberPerformance: DefaultMemberPerformance
        let performanceDataAccess: SwiftDataPerformanceDataAccess
        let exerciseRegistry: DefaultExerciseRegistry
    }

    private func makeContext() throws -> TestContext {
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
        return TestContext(
            memberPerformance: memberPerformance,
            performanceDataAccess: performanceDataAccess,
            exerciseRegistry: exerciseRegistry
        )
    }

    private func exercise(named name: String) -> ExerciseModel {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise: \(name)")
        }
        return exercise
    }

    private func derivedCurrentPB(
        memberPerformance: DefaultMemberPerformance,
        exerciseId: UUID
    ) throws -> PersonalBestModel? {
        try memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: exerciseId
        ).currentPB
    }

    // MARK: -- Draft completeness

    @Test
    func partialVariableRepExerciseIsTreatedAsIncomplete() {
        let dumbbellPress = exercise(named: "45-Degree Dumbbell Press")
        let draft = SetDraftValue(weight: 30, reps: nil)

        #expect(draft.isEmpty(for: dumbbellPress))
        #expect(draft.manualPBValues(for: dumbbellPress) == nil)
    }

    @Test
    func partialPlankEntryIsTreatedAsIncomplete() {
        let plank = exercise(named: "Plank")
        let draft = SetDraftValue(weight: 20, timeSeconds: nil)

        #expect(draft.isEmpty(for: plank))
        #expect(draft.manualPBValues(for: plank) == nil)
    }

    @Test
    func barbellLiftDefaultsRepsToFiveButRequiresExplicitEntryWhenCleared() {
        let freeSquat = exercise(named: "Free Squat")
        let initial = SetDraftValue.initial(for: freeSquat)

        #expect(initial.reps == 5)
        #expect(initial.isEmpty(for: freeSquat))

        let complete = SetDraftValue(weight: 100, reps: 5)
        #expect(complete.isEmpty(for: freeSquat) == false)
        #expect(complete.isValidManualPB(for: freeSquat))

        let clearedReps = SetDraftValue(weight: 100, reps: nil)
        #expect(clearedReps.isEmpty(for: freeSquat))
    }

    @Test
    func flatDumbbellPressAcceptsLowRepEntries() {
        let flatPress = exercise(named: "Flat Dumbbell Press")
        let draft = SetDraftValue(weight: 30, reps: 3)

        #expect(draft.isValidManualPB(for: flatPress))
    }

    @Test
    func flatDumbbellPressCanBeSavedWhenComplete() throws {
        let test = try makeContext()
        let flatPress = exercise(named: "Flat Dumbbell Press")
        let draft = SetDraftValue(weight: 30, reps: 8)

        #expect(draft.isValidManualPB(for: flatPress))

        let result = try test.memberPerformance.recordManualPB(
            exerciseId: flatPress.id,
            memberId: testMemberId,
            weight: 30,
            reps: 8,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )

        #expect(result.isNewPB)
        let pb = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: flatPress.id
        )
        #expect(pb?.weight == 30)
        #expect(pb?.reps == 8)
    }

    // MARK: -- Onboarding save behaviour

    @Test
    func savesNothingWhenNoDraftsAreProvided() throws {
        let test = try makeContext()
        let exercises = try test.exerciseRegistry.pbExercises()

        let savedCount = OnboardingPBSaver.saveDraftPBs(
            exercises: exercises,
            drafts: [:],
            memberPerformance: test.memberPerformance,
            memberId: testMemberId
        )

        #expect(savedCount == 0)
        #expect(try test.memberPerformance.currentPBs(memberId: testMemberId).isEmpty)
    }

    @Test
    func savesOnlyCompleteDraftsAndSkipsPartialOnes() throws {
        let test = try makeContext()
        let freeSquat = exercise(named: "Free Squat")
        let dumbbellPress = exercise(named: "45-Degree Dumbbell Press")

        let savedCount = OnboardingPBSaver.saveDraftPBs(
            exercises: [freeSquat, dumbbellPress],
            drafts: [
                freeSquat.id: SetDraftValue(weight: 100, reps: 5),
                dumbbellPress.id: SetDraftValue(weight: 30, reps: nil)
            ],
            memberPerformance: test.memberPerformance,
            memberId: testMemberId
        )

        #expect(savedCount == 1)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquat.id
        ) != nil)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: dumbbellPress.id
        ) == nil)
    }

    @Test
    func savesCompleteVariableRepExerciseWhenWeightAndRepsProvided() throws {
        let test = try makeContext()
        let dumbbellPress = exercise(named: "45-Degree Dumbbell Press")

        let savedCount = OnboardingPBSaver.saveDraftPBs(
            exercises: [dumbbellPress],
            drafts: [
                dumbbellPress.id: SetDraftValue(weight: 32, reps: 8)
            ],
            memberPerformance: test.memberPerformance,
            memberId: testMemberId
        )

        #expect(savedCount == 1)
        let pb = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: dumbbellPress.id
        )
        #expect(pb?.weight == 32)
        #expect(pb?.reps == 8)
    }

    @Test
    func savesCompletePlankWhenWeightAndTimeProvided() throws {
        let test = try makeContext()
        let plank = exercise(named: "Plank")

        let savedCount = OnboardingPBSaver.saveDraftPBs(
            exercises: [plank],
            drafts: [
                plank.id: SetDraftValue(weight: 25, timeSeconds: 90)
            ],
            memberPerformance: test.memberPerformance,
            memberId: testMemberId
        )

        #expect(savedCount == 1)
        let pb = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: plank.id
        )
        #expect(pb?.weight == 25)
        #expect(pb?.time == 90)
    }

    @Test
    func skipsIncompletePlankWithoutBlockingOtherSaves() throws {
        let test = try makeContext()
        let plank = exercise(named: "Plank")
        let chinUps = exercise(named: "Chin-ups")

        let savedCount = OnboardingPBSaver.saveDraftPBs(
            exercises: [plank, chinUps],
            drafts: [
                plank.id: SetDraftValue(weight: 25, timeSeconds: nil),
                chinUps.id: SetDraftValue(reps: 12)
            ],
            memberPerformance: test.memberPerformance,
            memberId: testMemberId
        )

        #expect(savedCount == 1)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: plank.id
        ) == nil)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: chinUps.id
        )?.reps == 12)
    }
}
#endif
