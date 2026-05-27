#if canImport(Testing)
import Foundation
import Testing
import SwiftData
@testable import GymPerformance

@Suite
struct ExerciseRegistryTests {

    private func makeRegistry() throws -> DefaultExerciseRegistry {
        let context = try TestHelpers.makeInMemoryContext()
        let configurationDataAccess = SwiftDataConfigurationDataAccess(context: context)
        return DefaultExerciseRegistry(configurationDataAccess: configurationDataAccess)
    }

    private func seededRegistry() throws -> DefaultExerciseRegistry {
        let registry = try makeRegistry()
        try registry.seedIfNeeded()
        return registry
    }

    private func exercise(named name: String) -> ExerciseModel {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise: \(name)")
        }
        return exercise
    }

    private func makeSet(
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil
    ) -> ModelSet {
        ModelSet(
            exerciseEntryId: UUID(),
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )
    }

    private func makeCurrentPB(
        exerciseId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil
    ) -> PersonalBestModel {
        PersonalBestModel(
            memberId: UUID(),
            exerciseId: exerciseId,
            setId: UUID(),
            weight: weight,
            reps: reps,
            time: time,
            distance: distance,
            achievedAt: Date()
        )
    }

    // MARK: -- Seeding

    @Test
    func testTC_E1_SeedIfNeededPopulatesStoreWhenEmpty() throws {
        let registry = try makeRegistry()

        try registry.seedIfNeeded()
        let exercises = try registry.allExercises()

        #expect(exercises.count == 19, "Expected 19 seeded exercises, got \(exercises.count)")
    }

    @Test
    func testTC_E2_SeedIfNeededDoesNotDuplicateWhenCalledTwice() throws {
        let registry = try makeRegistry()

        try registry.seedIfNeeded()
        try registry.seedIfNeeded()
        let exercises = try registry.allExercises()

        #expect(exercises.count == 19, "Expected 19 exercises after double seed, got \(exercises.count)")
    }

    @Test
    func testTC_E3_PbExercisesReturnsOnlyPbExerciseCategoryExercises() throws {
        let registry = try seededRegistry()
        let pbExercises = try registry.pbExercises()

        #expect(
            pbExercises.allSatisfy { $0.category == .pbExercise },
            "Expected only pbExercise category, got: \(pbExercises.map { $0.category.rawValue })"
        )
    }

    @Test
    func testTC_E4_ExercisesReturnedInDisplayOrder() throws {
        let registry = try seededRegistry()
        let exercises = try registry.allExercises()
        let displayOrders = exercises.map(\.displayOrder)

        #expect(
            displayOrders == displayOrders.sorted(),
            "Expected displayOrder ascending, got \(displayOrders)"
        )
        #expect(displayOrders == Array(1...19), "Expected displayOrder 1...19, got \(displayOrders)")
    }

    // MARK: -- PB Evaluation: heaviestWeightAtReps

    @Test
    func testTC_E5_FirstSetWithCorrectRepsIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Free Squat")
        let set = makeSet(weight: 80.0, reps: 5)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: nil)

        #expect(result == true, "Expected first valid set to be a PB")
    }

    @Test
    func testTC_E6_HeavierWeightAtCorrectRepsIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Free Squat")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 80.0, reps: 5)
        let set = makeSet(weight: 85.0, reps: 5)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == true, "Expected heavier weight at target reps to be a PB")
    }

    @Test
    func testTC_E7_SameWeightAtCorrectRepsIsNotAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Free Squat")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 80.0, reps: 5)
        let set = makeSet(weight: 80.0, reps: 5)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == false, "Expected matching weight not to be a PB")
    }

    @Test
    func testTC_E8_HeavierWeightAtWrongRepsIsNotAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Free Squat")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 80.0, reps: 5)
        let set = makeSet(weight: 85.0, reps: 3)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == false, "Expected heavier weight at wrong reps not to be a PB")
    }

    // MARK: -- PB Evaluation: bestWeightAndReps

    @Test
    func testTC_E9_FirstSetMeetingMinimumRepsIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let set = makeSet(weight: 20.0, reps: 5)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: nil)

        #expect(result == true, "Expected first set meeting minimum reps to be a PB")
    }

    @Test
    func testTC_E10_FirstSetBelowMinimumRepsIsNotAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let set = makeSet(weight: 20.0, reps: 4)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: nil)

        #expect(result == false, "Expected set below minimum reps not to be a PB")
    }

    @Test
    func testTC_E11_WeightIncreaseAtMinimumRepsIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 20.0, reps: 8)
        let set = makeSet(weight: 22.0, reps: 5)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == true, "Expected weight increase at minimum reps to be a PB")
    }

    @Test
    func testTC_E12_RepsIncreaseAtCurrentBestWeightIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 20.0, reps: 8)
        let set = makeSet(weight: 20.0, reps: 10)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == true, "Expected reps increase at current best weight to be a PB")
    }

    @Test
    func testTC_E13_WeightBelowCurrentBestIsNotAPBRegardlessOfReps() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 22.0, reps: 5)
        let set = makeSet(weight: 20.0, reps: 12)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == false, "Expected lower weight not to be a PB regardless of reps")
    }

    @Test
    func testTC_E14_WeightIncreaseButRepsBelowMinimumIsNotAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 20.0, reps: 8)
        let set = makeSet(weight: 22.0, reps: 4)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == false, "Expected weight increase below minimum reps not to be a PB")
    }

    // MARK: -- PB Evaluation: mostReps

    @Test
    func testTC_E15_MoreRepsIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Chin-ups")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, reps: 10)
        let set = makeSet(reps: 11)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == true, "Expected more reps to be a PB")
    }

    @Test
    func testTC_E16_SameRepsIsNotAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Chin-ups")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, reps: 10)
        let set = makeSet(reps: 10)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == false, "Expected matching reps not to be a PB")
    }

    // MARK: -- PB Evaluation: fastestTime

    @Test
    func testTC_E17_LowerTimeIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Ski 500m")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, time: 120.0)
        let set = makeSet(time: 118.5)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == true, "Expected lower time to be a PB")
    }

    @Test
    func testTC_E18_HigherTimeIsNotAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Ski 500m")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, time: 120.0)
        let set = makeSet(time: 122.0)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == false, "Expected higher time not to be a PB")
    }

    // MARK: -- PB Evaluation: longestDistance

    @Test
    func testTC_E19_LongerDistanceIsAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Bike")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, distance: 400.0)
        let set = makeSet(distance: 420.0)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == true, "Expected longer distance to be a PB")
    }

    @Test
    func testTC_E20_ShorterDistanceIsNotAPB() {
        let registry = try! makeRegistry()
        let exercise = exercise(named: "Bike")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, distance: 400.0)
        let set = makeSet(distance: 390.0)

        let result = registry.isPB(set: set, exercise: exercise, currentPB: currentPB)

        #expect(result == false, "Expected shorter distance not to be a PB")
    }
}

#else
import Foundation
import XCTest
import SwiftData
@testable import GymPerformance

final class ExerciseRegistryTests: XCTestCase {

    private func makeRegistry() throws -> DefaultExerciseRegistry {
        let context = try TestHelpers.makeInMemoryContext()
        let configurationDataAccess = SwiftDataConfigurationDataAccess(context: context)
        return DefaultExerciseRegistry(configurationDataAccess: configurationDataAccess)
    }

    private func seededRegistry() throws -> DefaultExerciseRegistry {
        let registry = try makeRegistry()
        try registry.seedIfNeeded()
        return registry
    }

    private func exercise(named name: String) -> ExerciseModel {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise: \(name)")
        }
        return exercise
    }

    private func makeSet(
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil
    ) -> ModelSet {
        ModelSet(
            exerciseEntryId: UUID(),
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )
    }

    private func makeCurrentPB(
        exerciseId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil
    ) -> PersonalBestModel {
        PersonalBestModel(
            memberId: UUID(),
            exerciseId: exerciseId,
            setId: UUID(),
            weight: weight,
            reps: reps,
            time: time,
            distance: distance,
            achievedAt: Date()
        )
    }

    func testTC_E1_SeedIfNeededPopulatesStoreWhenEmpty() throws {
        let registry = try makeRegistry()
        try registry.seedIfNeeded()
        XCTAssertEqual(try registry.allExercises().count, 19)
    }

    func testTC_E2_SeedIfNeededDoesNotDuplicateWhenCalledTwice() throws {
        let registry = try makeRegistry()
        try registry.seedIfNeeded()
        try registry.seedIfNeeded()
        XCTAssertEqual(try registry.allExercises().count, 19)
    }

    func testTC_E3_PbExercisesReturnsOnlyPbExerciseCategoryExercises() throws {
        let registry = try seededRegistry()
        XCTAssertTrue(try registry.pbExercises().allSatisfy { $0.category == .pbExercise })
    }

    func testTC_E4_ExercisesReturnedInDisplayOrder() throws {
        let registry = try seededRegistry()
        let displayOrders = try registry.allExercises().map(\.displayOrder)
        XCTAssertEqual(displayOrders, displayOrders.sorted())
        XCTAssertEqual(displayOrders, Array(1...19))
    }

    func testTC_E5_FirstSetWithCorrectRepsIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Free Squat")
        XCTAssertTrue(registry.isPB(set: makeSet(weight: 80.0, reps: 5), exercise: exercise, currentPB: nil))
    }

    func testTC_E6_HeavierWeightAtCorrectRepsIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Free Squat")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 80.0, reps: 5)
        XCTAssertTrue(registry.isPB(set: makeSet(weight: 85.0, reps: 5), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E7_SameWeightAtCorrectRepsIsNotAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Free Squat")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 80.0, reps: 5)
        XCTAssertFalse(registry.isPB(set: makeSet(weight: 80.0, reps: 5), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E8_HeavierWeightAtWrongRepsIsNotAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Free Squat")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 80.0, reps: 5)
        XCTAssertFalse(registry.isPB(set: makeSet(weight: 85.0, reps: 3), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E9_FirstSetMeetingMinimumRepsIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        XCTAssertTrue(registry.isPB(set: makeSet(weight: 20.0, reps: 5), exercise: exercise, currentPB: nil))
    }

    func testTC_E10_FirstSetBelowMinimumRepsIsNotAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        XCTAssertFalse(registry.isPB(set: makeSet(weight: 20.0, reps: 4), exercise: exercise, currentPB: nil))
    }

    func testTC_E11_WeightIncreaseAtMinimumRepsIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 20.0, reps: 8)
        XCTAssertTrue(registry.isPB(set: makeSet(weight: 22.0, reps: 5), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E12_RepsIncreaseAtCurrentBestWeightIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 20.0, reps: 8)
        XCTAssertTrue(registry.isPB(set: makeSet(weight: 20.0, reps: 10), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E13_WeightBelowCurrentBestIsNotAPBRegardlessOfReps() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 22.0, reps: 5)
        XCTAssertFalse(registry.isPB(set: makeSet(weight: 20.0, reps: 12), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E14_WeightIncreaseButRepsBelowMinimumIsNotAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "45-Degree Dumbbell Press")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, weight: 20.0, reps: 8)
        XCTAssertFalse(registry.isPB(set: makeSet(weight: 22.0, reps: 4), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E15_MoreRepsIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Chin-ups")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, reps: 10)
        XCTAssertTrue(registry.isPB(set: makeSet(reps: 11), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E16_SameRepsIsNotAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Chin-ups")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, reps: 10)
        XCTAssertFalse(registry.isPB(set: makeSet(reps: 10), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E17_LowerTimeIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Ski 500m")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, time: 120.0)
        XCTAssertTrue(registry.isPB(set: makeSet(time: 118.5), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E18_HigherTimeIsNotAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Ski 500m")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, time: 120.0)
        XCTAssertFalse(registry.isPB(set: makeSet(time: 122.0), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E19_LongerDistanceIsAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Bike")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, distance: 400.0)
        XCTAssertTrue(registry.isPB(set: makeSet(distance: 420.0), exercise: exercise, currentPB: currentPB))
    }

    func testTC_E20_ShorterDistanceIsNotAPB() throws {
        let registry = try makeRegistry()
        let exercise = exercise(named: "Bike")
        let currentPB = makeCurrentPB(exerciseId: exercise.id, distance: 400.0)
        XCTAssertFalse(registry.isPB(set: makeSet(distance: 390.0), exercise: exercise, currentPB: currentPB))
    }
}
#endif
