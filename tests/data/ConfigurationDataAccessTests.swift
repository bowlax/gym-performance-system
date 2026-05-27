#if canImport(Testing)
import Foundation
import Testing
import SwiftData
@testable import GymPerformance

@Suite
struct ConfigurationDataAccessTests {

    @Test
    func testTC_C1_FetchExercisesReturnsEmptyWhenStoreIsEmpty() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let exercises = try sut.fetchExercises()
        #expect(exercises.isEmpty)
    }

    @Test
    func testTC_C2_SeedExercisesPopulatesTheStore() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let seeded: [ExerciseModel] = [
            ExerciseModel(
                name: "Back Squat",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeight,
                displayOrder: 1
            ),
            ExerciseModel(
                name: "400m Run",
                category: .conditioning,
                measurementType: .timeOnly,
                displayOrder: 2,
                isActive: true
            )
        ]

        try sut.seedExercises(seeded)
        let fetched = try sut.fetchExercises()

        #expect(fetched.count == seeded.count)
        #expect(Set(fetched.map(\.id)) == Set(seeded.map(\.id)))
    }

    @Test
    func testTC_C3_FetchExercisesReturnsOnlyActiveExercises() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let active = ExerciseModel(
            name: "Active",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1,
            isActive: true
        )

        let inactive = ExerciseModel(
            name: "Inactive",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 2,
            isActive: false
        )

        try sut.seedExercises([active, inactive])
        let fetched = try sut.fetchExercises()

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == active.id)
        #expect(fetched.allSatisfy { $0.isActive == true })
    }

    @Test
    func testTC_C4_FetchExercisesReturnsResultsOrderedByDisplayOrder() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let e3 = ExerciseModel(
            name: "E3",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 3
        )
        let e1 = ExerciseModel(
            name: "E1",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )
        let e2 = ExerciseModel(
            name: "E2",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 2
        )

        try sut.seedExercises([e3, e1, e2])
        let fetched = try sut.fetchExercises()

        #expect(fetched.map(\.displayOrder) == [1, 2, 3])
    }

    @Test
    func testTC_C5_FetchExerciseByIdReturnsCorrectExercise() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let a = ExerciseModel(
            name: "A",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )
        let b = ExerciseModel(
            name: "B",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 2
        )

        try sut.seedExercises([a, b])
        let fetched = try sut.fetchExercise(id: b.id)

        #expect(fetched?.id == b.id)
        #expect(fetched?.name == "B")
    }

    @Test
    func testTC_C6_FetchExerciseByIdReturnsNilForUnknownId() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let a = ExerciseModel(
            name: "A",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )

        try sut.seedExercises([a])
        let fetched = try sut.fetchExercise(id: UUID())

        #expect(fetched == nil)
    }

    @Test
    func testTC_C7_FetchExercisesByCategoryReturnsOnlyMatchingExercises() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let pbExercise = ExerciseModel(
            name: "Back Squat",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )
        let conditioningExercise = ExerciseModel(
            name: "400m Run",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 2
        )

        context.insert(pbExercise)
        context.insert(conditioningExercise)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ExerciseModel>())
        let storedSummary = stored.map { "\($0.name):\($0.category.rawValue)" }.joined(separator: ", ")
        #expect(stored.count == 2, "Expected 2 exercises in store before fetch, got \(stored.count): [\(storedSummary)]")

        let pbFetched = try sut.fetchExercises(category: .pbExercise)
        let pbSummary = pbFetched.map { "\($0.name):\($0.category.rawValue)" }.joined(separator: ", ")
        #expect(
            pbFetched.count == 1,
            "Expected exactly 1 pbExercise, got \(pbFetched.count): [\(pbSummary)]. Store contains: [\(storedSummary)]"
        )
        #expect(
            pbFetched.allSatisfy { $0.category == .pbExercise },
            "pbExercise fetch returned non-pbExercise categories: [\(pbSummary)]"
        )
        #expect(pbFetched.first?.id == pbExercise.id, "Expected Back Squat id, got \(String(describing: pbFetched.first?.id))")

        let condFetched = try sut.fetchExercises(category: .conditioning)
        let condSummary = condFetched.map { "\($0.name):\($0.category.rawValue)" }.joined(separator: ", ")
        #expect(
            condFetched.count == 1,
            "Expected exactly 1 conditioning exercise, got \(condFetched.count): [\(condSummary)]. Store contains: [\(storedSummary)]"
        )
        #expect(
            condFetched.allSatisfy { $0.category == .conditioning },
            "conditioning fetch returned non-conditioning categories: [\(condSummary)]"
        )
        #expect(
            condFetched.first?.id == conditioningExercise.id,
            "Expected 400m Run id, got \(String(describing: condFetched.first?.id))"
        )
    }

    @Test
    func testTC_C8_SeedDoesNotDuplicateIfCalledTwice() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let e = ExerciseModel(
            name: "E",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )

        try sut.seedExercises([e])
        try sut.seedExercises([e])

        let all = try context.fetch(FetchDescriptor<ExerciseModel>())
        #expect(all.count == 1)
    }
}

#else
import XCTest
import SwiftData

final class ConfigurationDataAccessTests: XCTestCase {

    func testTC_C1_FetchExercisesReturnsEmptyWhenStoreIsEmpty() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)
        XCTAssertTrue(try sut.fetchExercises().isEmpty)
    }

    func testTC_C2_SeedExercisesPopulatesTheStore() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let seeded: [ExerciseModel] = [
            ExerciseModel(
                name: "Back Squat",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeight,
                displayOrder: 1
            ),
            ExerciseModel(
                name: "400m Run",
                category: .conditioning,
                measurementType: .timeOnly,
                displayOrder: 2,
                isActive: true
            )
        ]

        try sut.seedExercises(seeded)
        let fetched = try sut.fetchExercises()
        XCTAssertEqual(fetched.count, seeded.count)
        XCTAssertEqual(Set(fetched.map(\.id)), Set(seeded.map(\.id)))
    }

    func testTC_C3_FetchExercisesReturnsOnlyActiveExercises() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let active = ExerciseModel(
            name: "Active",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1,
            isActive: true
        )

        let inactive = ExerciseModel(
            name: "Inactive",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 2,
            isActive: false
        )

        try sut.seedExercises([active, inactive])
        let fetched = try sut.fetchExercises()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, active.id)
        XCTAssertTrue(fetched.allSatisfy { $0.isActive == true })
    }

    func testTC_C4_FetchExercisesReturnsResultsOrderedByDisplayOrder() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let e3 = ExerciseModel(
            name: "E3",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 3
        )
        let e1 = ExerciseModel(
            name: "E1",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )
        let e2 = ExerciseModel(
            name: "E2",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 2
        )

        try sut.seedExercises([e3, e1, e2])
        let fetched = try sut.fetchExercises()
        XCTAssertEqual(fetched.map(\.displayOrder), [1, 2, 3])
    }

    func testTC_C5_FetchExerciseByIdReturnsCorrectExercise() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let a = ExerciseModel(
            name: "A",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )
        let b = ExerciseModel(
            name: "B",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 2
        )

        try sut.seedExercises([a, b])
        let fetched = try sut.fetchExercise(id: b.id)
        XCTAssertEqual(fetched?.id, b.id)
        XCTAssertEqual(fetched?.name, "B")
    }

    func testTC_C6_FetchExerciseByIdReturnsNilForUnknownId() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let a = ExerciseModel(
            name: "A",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )

        try sut.seedExercises([a])
        let fetched = try sut.fetchExercise(id: UUID())
        XCTAssertNil(fetched)
    }

    func testTC_C7_FetchExercisesByCategoryReturnsOnlyMatchingExercises() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let pbExercise = ExerciseModel(
            name: "Back Squat",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )
        let conditioningExercise = ExerciseModel(
            name: "400m Run",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 2
        )

        context.insert(pbExercise)
        context.insert(conditioningExercise)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ExerciseModel>())
        let storedSummary = stored.map { "\($0.name):\($0.category.rawValue)" }.joined(separator: ", ")
        XCTAssertEqual(stored.count, 2, "Expected 2 exercises in store before fetch, got \(stored.count): [\(storedSummary)]")

        let pbFetched = try sut.fetchExercises(category: .pbExercise)
        let pbSummary = pbFetched.map { "\($0.name):\($0.category.rawValue)" }.joined(separator: ", ")
        XCTAssertEqual(
            pbFetched.count,
            1,
            "Expected exactly 1 pbExercise, got \(pbFetched.count): [\(pbSummary)]. Store contains: [\(storedSummary)]"
        )
        XCTAssertTrue(
            pbFetched.allSatisfy { $0.category == .pbExercise },
            "pbExercise fetch returned non-pbExercise categories: [\(pbSummary)]"
        )
        XCTAssertEqual(pbFetched.first?.id, pbExercise.id, "Expected Back Squat id")

        let condFetched = try sut.fetchExercises(category: .conditioning)
        let condSummary = condFetched.map { "\($0.name):\($0.category.rawValue)" }.joined(separator: ", ")
        XCTAssertEqual(
            condFetched.count,
            1,
            "Expected exactly 1 conditioning exercise, got \(condFetched.count): [\(condSummary)]. Store contains: [\(storedSummary)]"
        )
        XCTAssertTrue(
            condFetched.allSatisfy { $0.category == .conditioning },
            "conditioning fetch returned non-conditioning categories: [\(condSummary)]"
        )
        XCTAssertEqual(condFetched.first?.id, conditioningExercise.id, "Expected 400m Run id")
    }

    func testTC_C8_SeedDoesNotDuplicateIfCalledTwice() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataConfigurationDataAccess(context: context)

        let e = ExerciseModel(
            name: "E",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeight,
            displayOrder: 1
        )

        try sut.seedExercises([e])
        try sut.seedExercises([e])
        let all = try context.fetch(FetchDescriptor<ExerciseModel>())
        XCTAssertEqual(all.count, 1)
    }
}
#endif

