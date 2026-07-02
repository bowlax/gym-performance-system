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

    // MARK: -- Seeding

    @Test
    func testTC_E1_SeedIfNeededPopulatesStoreWhenEmpty() throws {
        let registry = try makeRegistry()

        try registry.seedIfNeeded()
        let exercises = try registry.allExercises()

        #expect(exercises.count == 19, "Expected 19 seeded exercises, got \(exercises.count)")
    }

    @Test
    func testTC_E21_SeedIfNeededSyncsMinimumRepsOnExistingStore() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let configurationDataAccess = SwiftDataConfigurationDataAccess(context: context)
        let legacyExercise = ExerciseModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            name: "Flat Dumbbell Press",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .bestWeightAndReps,
            minimumReps: 6,
            displayOrder: 9
        )
        context.insert(legacyExercise)
        try context.save()

        let registry = DefaultExerciseRegistry(configurationDataAccess: configurationDataAccess)
        try registry.seedIfNeeded()

        let updated = try configurationDataAccess.fetchExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        )
        #expect(updated?.minimumReps == nil)
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

    private enum PBEvaluationVectorFixtures {
        static let all: [PBEvaluationVector] = {
            do {
                return try PBEvaluationVectorLoader.load()
            } catch {
                fatalError("Failed to load PB evaluation vectors: \(error)")
            }
        }()
    }

    // MARK: -- PB Evaluation (shared vectors)

    @Test(arguments: PBEvaluationVectorFixtures.all)
    func testPBEvaluationVector(_ vector: PBEvaluationVector) throws {
        let registry = try makeRegistry()
        let result = PBEvaluationVectorRunner.evaluate(vector, registry: registry)

        #expect(
            result == vector.expectsIsPB,
            "[\(vector.id)] \(vector.description)"
        )
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

    func testPBEvaluationVectors() throws {
        let registry = try makeRegistry()
        let vectors = try PBEvaluationVectorLoader.load()

        for vector in vectors {
            try XCTContext.runActivity(named: vector.id) { _ in
                let result = PBEvaluationVectorRunner.evaluate(vector, registry: registry)
                XCTAssertEqual(
                    result,
                    vector.expectsIsPB,
                    "[\(vector.id)] \(vector.description)"
                )
            }
        }
    }
}
#endif
