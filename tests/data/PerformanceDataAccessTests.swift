#if canImport(Testing)
import Foundation
import Testing
import SwiftData
@testable import GymPerformance

@Suite
struct PerformanceDataAccessTests {

    // MARK: -- Sessions

    @Test
    func testTC_P1_SaveAndFetchSession() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let session = SessionModel(memberId: memberId, date: Date())

        try sut.saveSession(session)
        let fetched = try sut.fetchSessions(memberId: memberId)

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == session.id)
    }

    @Test
    func testTC_P2_FetchSessionsReturnsOnlySessionsForTheSpecifiedMember() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberA = UUID()
        let memberB = UUID()

        try sut.saveSession(SessionModel(memberId: memberA, date: Date()))
        try sut.saveSession(SessionModel(memberId: memberB, date: Date()))

        let fetched = try sut.fetchSessions(memberId: memberA)
        #expect(fetched.allSatisfy { $0.memberId == memberA })
    }

    @Test
    func testTC_P3_FetchSessionById() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)

        let fetched = try sut.fetchSession(id: session.id)
        #expect(fetched?.id == session.id)
    }

    @Test
    func testTC_P4_FetchSessionByIdReturnsNilForUnknownId() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        try sut.saveSession(SessionModel(memberId: UUID(), date: Date()))
        let fetched = try sut.fetchSession(id: UUID())
        #expect(fetched == nil)
    }

    @Test
    func testTC_P5_UpdateSessionPersistsChanges() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date(), notes: nil)
        try sut.saveSession(session)

        let createdAt = session.createdAt
        session.notes = "Updated notes"
        session.updatedAt = Date().addingTimeInterval(1)
        try sut.updateSession(session)

        let fetched = try sut.fetchSession(id: session.id)
        #expect(fetched?.notes == "Updated notes")
        #expect((fetched?.updatedAt ?? .distantPast) > createdAt)
    }

    @Test
    func testTC_P6_SessionsCannotBeDeleted() throws {
        let root = TestHelpers.repositoryRootURL()
        let path = root.appendingPathComponent("src/data/performance-data-access/PerformanceDataAccess.swift")
        let contents = try String(contentsOf: path)
        #expect(contents.contains("deleteSession") == false)
    }

    // MARK: -- Exercise Entries

    @Test
    func testTC_P7_SaveAndFetchExerciseEntry() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)

        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let fetched = try sut.fetchExerciseEntries(sessionId: session.id)
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == entry.id)
    }

    @Test
    func testTC_P8_FetchExerciseEntriesReturnsOnlyEntriesForTheSpecifiedSession() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let s1 = SessionModel(memberId: UUID(), date: Date())
        let s2 = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(s1)
        try sut.saveSession(s2)

        try sut.saveExerciseEntry(ExerciseEntryModel(sessionId: s1.id, exerciseId: UUID()))
        try sut.saveExerciseEntry(ExerciseEntryModel(sessionId: s2.id, exerciseId: UUID()))

        let fetched = try sut.fetchExerciseEntries(sessionId: s1.id)
        #expect(fetched.allSatisfy { $0.sessionId == s1.id })
    }

    @Test
    func testTC_P9_UpdateExerciseEntryPersistsChanges() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)

        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let createdAt = entry.createdAt
        entry.updatedAt = Date().addingTimeInterval(1)
        try sut.updateExerciseEntry(entry)

        let fetched = try sut.fetchExerciseEntries(sessionId: session.id)
        #expect(fetched.first?.updatedAt ?? .distantPast > createdAt)
    }

    // MARK: -- Sets

    @Test
    func testTC_P10_SaveAndFetchSet() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let set = ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5)
        try sut.saveSet(set)

        let fetched = try sut.fetchSets(exerciseEntryId: entry.id)
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == set.id)
    }

    @Test
    func testTC_P11_MultipleSetsPerExerciseEntry() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        try sut.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 70, reps: 5))
        try sut.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 75, reps: 5))
        try sut.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5))

        let fetched = try sut.fetchSets(exerciseEntryId: entry.id)
        #expect(fetched.count == 3)
    }

    @Test
    func testTC_P12_UpdateSetPersistsChanges() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let set = ModelSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5)
        try sut.saveSet(set)

        let createdAt = set.createdAt
        set.weight = 85.0
        set.updatedAt = Date().addingTimeInterval(1)
        try sut.updateSet(set)

        let fetched = try sut.fetchSets(exerciseEntryId: entry.id)
        #expect(fetched.first?.weight == 85.0)
        #expect((fetched.first?.updatedAt ?? .distantPast) > createdAt)
    }

    @Test
    func testTC_P13_SetsCannotBeDeleted() throws {
        let root = TestHelpers.repositoryRootURL()
        let path = root.appendingPathComponent("src/data/performance-data-access/PerformanceDataAccess.swift")
        let contents = try String(contentsOf: path)
        #expect(contents.contains("deleteSet") == false)
        #expect(contents.contains("deleteModelSet") == false)
    }

    // MARK: -- Personal Bests

    @Test
    func testTC_P14_SaveAndFetchAllPBs() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()
        let pb = PersonalBestModel(
            memberId: memberId,
            exerciseId: exerciseId,
            weight: 80,
            reps: 5,
            achievedAt: Date()
        )
        try sut.savePersonalBest(pb)

        let fetched = try sut.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == pb.id)
    }

    @Test
    func testTC_P15_FetchAllPBsReturnsOnlyMatchingMemberAndExercise() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()

        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 80,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-10)
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 85,
                reps: 5,
                achievedAt: Date()
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: UUID(),
                exerciseId: exerciseId,
                weight: 90,
                reps: 5,
                achievedAt: Date()
            )
        )

        let fetched = try sut.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.memberId == memberId && $0.exerciseId == exerciseId })
    }

    @Test
    func testTC_P16_FetchAllPBsReturnsFullHistorySortedByAchievedAtDescending() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()

        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 70,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-30)
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 75,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-20)
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 80,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-10)
            )
        )

        let fetched = try sut.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        #expect(fetched.count == 3)
        #expect(fetched.map(\.weight) == [80.0, 75.0, 70.0])
    }

    @Test
    func testTC_P17_UpsertExerciseResetPersistsResetDate() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()
        let resetAt = Calendar(identifier: .gregorian).startOfDay(for: Date())

        let reset = try sut.upsertExerciseReset(
            memberId: memberId,
            exerciseId: exerciseId,
            resetAt: resetAt
        )

        let fetched = try sut.fetchExerciseReset(memberId: memberId, exerciseId: exerciseId)
        #expect(fetched?.id == reset.id)
        #expect(fetched?.resetAt == resetAt)
    }

    @Test
    func testTC_P18_PersonalBestsCannotBeDeleted() throws {
        let root = TestHelpers.repositoryRootURL()
        let path = root.appendingPathComponent("src/data/performance-data-access/PerformanceDataAccess.swift")
        let contents = try String(contentsOf: path)
        #expect(contents.contains("deletePersonalBest") == false)
        #expect(contents.contains("deletePB") == false)
    }
}

#else
import XCTest
import SwiftData

final class PerformanceDataAccessTests: XCTestCase {

    func testTC_P1_SaveAndFetchSession() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let session = SessionModel(memberId: memberId, date: Date())
        try sut.saveSession(session)

        let fetched = try sut.fetchSessions(memberId: memberId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, session.id)
    }

    func testTC_P2_FetchSessionsReturnsOnlySessionsForTheSpecifiedMember() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberA = UUID()
        let memberB = UUID()

        try sut.saveSession(SessionModel(memberId: memberA, date: Date()))
        try sut.saveSession(SessionModel(memberId: memberB, date: Date()))

        let fetched = try sut.fetchSessions(memberId: memberA)
        XCTAssertTrue(fetched.allSatisfy { $0.memberId == memberA })
    }

    func testTC_P3_FetchSessionById() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let fetched = try sut.fetchSession(id: session.id)
        XCTAssertEqual(fetched?.id, session.id)
    }

    func testTC_P4_FetchSessionByIdReturnsNilForUnknownId() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        try sut.saveSession(SessionModel(memberId: UUID(), date: Date()))
        XCTAssertNil(try sut.fetchSession(id: UUID()))
    }

    func testTC_P5_UpdateSessionPersistsChanges() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date(), notes: nil)
        try sut.saveSession(session)

        let createdAt = session.createdAt
        session.notes = "Updated notes"
        session.updatedAt = Date().addingTimeInterval(1)
        try sut.updateSession(session)

        let fetched = try sut.fetchSession(id: session.id)
        XCTAssertEqual(fetched?.notes, "Updated notes")
        XCTAssertTrue((fetched?.updatedAt ?? .distantPast) > createdAt)
    }

    func testTC_P6_SessionsCannotBeDeleted() throws {
        let root = TestHelpers.repositoryRootURL()
        let path = root.appendingPathComponent("src/data/performance-data-access/PerformanceDataAccess.swift")
        let contents = try String(contentsOf: path)
        XCTAssertFalse(contents.contains("deleteSession"))
    }

    func testTC_P7_SaveAndFetchExerciseEntry() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let fetched = try sut.fetchExerciseEntries(sessionId: session.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, entry.id)
    }

    func testTC_P8_FetchExerciseEntriesReturnsOnlyEntriesForTheSpecifiedSession() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let s1 = SessionModel(memberId: UUID(), date: Date())
        let s2 = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(s1)
        try sut.saveSession(s2)

        try sut.saveExerciseEntry(ExerciseEntryModel(sessionId: s1.id, exerciseId: UUID()))
        try sut.saveExerciseEntry(ExerciseEntryModel(sessionId: s2.id, exerciseId: UUID()))

        let fetched = try sut.fetchExerciseEntries(sessionId: s1.id)
        XCTAssertTrue(fetched.allSatisfy { $0.sessionId == s1.id })
    }

    func testTC_P9_UpdateExerciseEntryPersistsChanges() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let createdAt = entry.createdAt
        entry.updatedAt = Date().addingTimeInterval(1)
        try sut.updateExerciseEntry(entry)

        let fetched = try sut.fetchExerciseEntries(sessionId: session.id)
        XCTAssertTrue((fetched.first?.updatedAt ?? .distantPast) > createdAt)
    }

    func testTC_P10_SaveAndFetchSet() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let set = ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5)
        try sut.saveSet(set)
        let fetched = try sut.fetchSets(exerciseEntryId: entry.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, set.id)
    }

    func testTC_P11_MultipleSetsPerExerciseEntry() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        try sut.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 70, reps: 5))
        try sut.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 75, reps: 5))
        try sut.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5))

        let fetched = try sut.fetchSets(exerciseEntryId: entry.id)
        XCTAssertEqual(fetched.count, 3)
    }

    func testTC_P12_UpdateSetPersistsChanges() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let session = SessionModel(memberId: UUID(), date: Date())
        try sut.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        try sut.saveExerciseEntry(entry)

        let set = ModelSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5)
        try sut.saveSet(set)

        let createdAt = set.createdAt
        set.weight = 85.0
        set.updatedAt = Date().addingTimeInterval(1)
        try sut.updateSet(set)

        let fetched = try sut.fetchSets(exerciseEntryId: entry.id)
        XCTAssertEqual(fetched.first?.weight, 85.0)
        XCTAssertTrue((fetched.first?.updatedAt ?? .distantPast) > createdAt)
    }

    func testTC_P13_SetsCannotBeDeleted() throws {
        let root = TestHelpers.repositoryRootURL()
        let path = root.appendingPathComponent("src/data/performance-data-access/PerformanceDataAccess.swift")
        let contents = try String(contentsOf: path)
        XCTAssertFalse(contents.contains("deleteSet"))
        XCTAssertFalse(contents.contains("deleteModelSet"))
    }

    func testTC_P14_SaveAndFetchAllPBs() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()
        let pb = PersonalBestModel(
            memberId: memberId,
            exerciseId: exerciseId,
            weight: 80,
            reps: 5,
            achievedAt: Date()
        )
        try sut.savePersonalBest(pb)

        let fetched = try sut.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, pb.id)
    }

    func testTC_P15_FetchAllPBsReturnsOnlyMatchingMemberAndExercise() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()

        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 80,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-10)
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 85,
                reps: 5,
                achievedAt: Date()
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: UUID(),
                exerciseId: exerciseId,
                weight: 90,
                reps: 5,
                achievedAt: Date()
            )
        )

        let fetched = try sut.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertTrue(fetched.allSatisfy { $0.memberId == memberId && $0.exerciseId == exerciseId })
    }

    func testTC_P16_FetchAllPBsReturnsFullHistorySortedByAchievedAtDescending() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()

        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 70,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-30)
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 75,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-20)
            )
        )
        try sut.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exerciseId,
                weight: 80,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-10)
            )
        )

        let fetched = try sut.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched.map(\.weight), [80.0, 75.0, 70.0])
    }

    func testTC_P17_UpsertExerciseResetPersistsResetDate() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let sut = SwiftDataPerformanceDataAccess(context: context)

        let memberId = UUID()
        let exerciseId = UUID()
        let resetAt = Calendar(identifier: .gregorian).startOfDay(for: Date())

        let reset = try sut.upsertExerciseReset(
            memberId: memberId,
            exerciseId: exerciseId,
            resetAt: resetAt
        )

        let fetched = try sut.fetchExerciseReset(memberId: memberId, exerciseId: exerciseId)
        XCTAssertEqual(fetched?.id, reset.id)
        XCTAssertEqual(fetched?.resetAt, resetAt)
    }

    func testTC_P18_PersonalBestsCannotBeDeleted() throws {
        let root = TestHelpers.repositoryRootURL()
        let path = root.appendingPathComponent("src/data/performance-data-access/PerformanceDataAccess.swift")
        let contents = try String(contentsOf: path)
        XCTAssertFalse(contents.contains("deletePersonalBest"))
        XCTAssertFalse(contents.contains("deletePB"))
    }
}
#endif

