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
            performanceDataAccess: performanceDataAccess
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
    func fixedRepExerciseAcceptsWeightOnlyDraft() {
        let freeSquat = exercise(named: "Free Squat")
        let draft = SetDraftValue(weight: 100, reps: nil)

        #expect(draft.isEmpty(for: freeSquat) == false)
        #expect(draft.manualPBValues(for: freeSquat) != nil)
        #expect(draft.isValidManualPB(for: freeSquat))
    }

    // MARK: -- Manual PB validation

    @Test
    func flatDumbbellPressRequiresWeightAndReps() {
        let flatPress = exercise(named: "Flat Dumbbell Press")

        let weightOnly = SetDraftValue(weight: 30, reps: nil)
        #expect(weightOnly.isValidManualPB(for: flatPress) == false)

        let complete = SetDraftValue(weight: 30, reps: 8)
        #expect(complete.isValidManualPB(for: flatPress))
    }

    @Test
    func flatDumbbellPressRejectsRepsBelowMinimum() {
        let flatPress = exercise(named: "Flat Dumbbell Press")
        let draft = SetDraftValue(weight: 30, reps: 4)

        #expect(draft.isValidManualPB(for: flatPress) == false)
        #expect(draft.manualPBValidationMessage(for: flatPress) == "This exercise requires at least 6 reps for a PB.")
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
            distance: nil
        )

        #expect(result.isNewPB)
        let pb = try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
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
        #expect(try test.performanceDataAccess.fetchCurrentPBs(memberId: testMemberId).isEmpty)
    }

    @Test
    func savesOnlyCompleteDraftsAndSkipsPartialOnes() throws {
        let test = try makeContext()
        let freeSquat = exercise(named: "Free Squat")
        let dumbbellPress = exercise(named: "45-Degree Dumbbell Press")

        let savedCount = OnboardingPBSaver.saveDraftPBs(
            exercises: [freeSquat, dumbbellPress],
            drafts: [
                freeSquat.id: SetDraftValue(weight: 100, reps: nil),
                dumbbellPress.id: SetDraftValue(weight: 30, reps: nil)
            ],
            memberPerformance: test.memberPerformance,
            memberId: testMemberId
        )

        #expect(savedCount == 1)
        #expect(try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
            exerciseId: freeSquat.id
        ) != nil)
        #expect(try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
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
        let pb = try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
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
        let pb = try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
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
        #expect(try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
            exerciseId: plank.id
        ) == nil)
        #expect(try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
            exerciseId: chinUps.id
        )?.reps == 12)
    }
}
#endif
