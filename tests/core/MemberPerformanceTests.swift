#if canImport(Testing)
import Foundation
import Testing
import SwiftData
@testable import GymPerformance

@Suite
struct MemberPerformanceTests {

    private let testMemberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    private struct TestContext {
        let memberPerformance: DefaultMemberPerformance
        let performanceDataAccess: SwiftDataPerformanceDataAccess
        let exerciseRegistry: DefaultExerciseRegistry
        let context: ModelContext
    }

    private func makeMemberPerformance() throws -> TestContext {
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
            exerciseRegistry: exerciseRegistry,
            context: context
        )
    }

    private func seedExerciseId(named name: String) -> UUID {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise: \(name)")
        }
        return exercise.id
    }

    private func makeSession(date: Date = Date()) -> SessionModel {
        SessionModel(memberId: testMemberId, date: date)
    }

    private func makeEntry(sessionId: UUID, exerciseId: UUID) -> ExerciseEntryModel {
        ExerciseEntryModel(sessionId: sessionId, exerciseId: exerciseId)
    }

    private func makeSet(
        exerciseEntryId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil
    ) -> ModelSet {
        ModelSet(
            exerciseEntryId: exerciseEntryId,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )
    }

    private func saveExistingPB(
        performanceDataAccess: SwiftDataPerformanceDataAccess,
        exerciseId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil,
        achievedAt: Date = Date(),
        entryType: PBEntryType = .manualEntry
    ) throws -> PersonalBestModel {
        let pb = PersonalBestModel(
            memberId: testMemberId,
            exerciseId: exerciseId,
            setId: nil,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance,
            achievedAt: achievedAt,
            entryType: entryType
        )
        try performanceDataAccess.savePersonalBest(pb)
        return pb
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

    private func mondayCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: -- Session Recording

    @Test
    func testTC_MP1_SaveAValidSessionWithOneExerciseAndOneSet() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5)

        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        #expect(try test.performanceDataAccess.fetchSession(id: session.id) != nil)
        #expect(try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id).count == 1)
        #expect(try test.performanceDataAccess.fetchSets(exerciseEntryId: entry.id).count == 1)
        #expect(result.newPBs.count == 1)
        #expect(result.newPBs.first?.exerciseId == freeSquatId)
        #expect(result.newPBs.first?.entryType == .sessionDerived)
    }

    @Test
    func testTC_MP2_SaveASessionWhereNoPBIsAchieved() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 100.0,
            reps: 5
        )

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 90.0, reps: 5)

        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        #expect(result.newPBs.isEmpty)
        let currentPB = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(currentPB?.weight == 100.0)
    }

    @Test
    func testTC_MP3_SaveASessionThatBeatsAnExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let earlierSession = makeSession(date: Date().addingTimeInterval(-86_400))
        let earlierEntry = makeEntry(sessionId: earlierSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            earlierSession,
            entries: [earlierEntry],
            sets: [earlierEntry.id: [makeSet(exerciseEntryId: earlierEntry.id, weight: 80.0, reps: 5)]]
        )

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)

        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        #expect(result.newPBs.count == 1)
        #expect(result.newPBs.first?.weight == 85.0)
        #expect(result.newPBs.first?.reps == 5)

        let currentPB = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(currentPB?.weight == 85.0)
        #expect(currentPB?.setId == set.id)
        #expect(
            try test.performanceDataAccess.fetchAllPBs(
                memberId: testMemberId,
                exerciseId: freeSquatId
            ).isEmpty
        )
    }

    @Test
    func testTC_MP4_SaveASessionWithMultipleExercisesMultiplePBs() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let overheadPressId = seedExerciseId(named: "Overhead Press")

        let session = makeSession()
        let squatEntry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let pressEntry = makeEntry(sessionId: session.id, exerciseId: overheadPressId)
        let squatSet = makeSet(exerciseEntryId: squatEntry.id, weight: 80.0, reps: 5)
        let pressSet = makeSet(exerciseEntryId: pressEntry.id, weight: 50.0, reps: 5)

        let result = try test.memberPerformance.saveSession(
            session,
            entries: [squatEntry, pressEntry],
            sets: [
                squatEntry.id: [squatSet],
                pressEntry.id: [pressSet]
            ]
        )

        #expect(result.newPBs.count == 2)
    }

    @Test
    func testTC_MP5_SaveASessionWithAConditioningExerciseNoPBEvaluated() throws {
        let test = try makeMemberPerformance()

        let conditioningExercise = ExerciseModel(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            name: "400m Run",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 100
        )
        test.context.insert(conditioningExercise)
        try test.context.save()

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: conditioningExercise.id)
        let set = makeSet(exerciseEntryId: entry.id, time: 92.0)

        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        #expect(result.newPBs.isEmpty)
        #expect(try test.performanceDataAccess.fetchSession(id: session.id) != nil)
        #expect(try test.performanceDataAccess.fetchSets(exerciseEntryId: entry.id).count == 1)
        #expect(
            try test.performanceDataAccess.fetchAllPBs(
                memberId: testMemberId,
                exerciseId: conditioningExercise.id
            ).isEmpty
        )
    }

    @Test
    func testTC_MP6_SaveASessionWithNoExerciseEntriesAsAttendanceRecord() throws {
        let test = try makeMemberPerformance()
        let session = SessionModel(memberId: testMemberId, date: Date(), notes: "Attendance only")

        let result = try test.memberPerformance.saveSession(session, entries: [], sets: [:])

        #expect(result.newPBs.isEmpty)
        #expect(try test.performanceDataAccess.fetchSession(id: session.id) != nil)
        #expect(try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id).isEmpty)
    }

    @Test
    func testTC_MP7_RejectASetWithMissingRequiredMeasurementFields() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: nil)

        #expect(throws: MemberPerformanceError.invalidMeasurementFields(.weightAndReps)) {
            _ = try test.memberPerformance.saveSession(
                session,
                entries: [entry],
                sets: [entry.id: [set]]
            )
        }

        let storedSessions = try test.context.fetch(FetchDescriptor<SessionModel>())
        #expect(storedSessions.isEmpty)
    }

    @Test
    func testTC_MP8_UpdateASessionDoesNotReEvaluatePBs() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5)

        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        let pbBeforeUpdate = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )

        session.notes = "Updated notes"
        session.updatedAt = Date().addingTimeInterval(1)
        try test.memberPerformance.updateSession(session)

        let fetchedSession = try test.performanceDataAccess.fetchSession(id: session.id)
        let pbAfterUpdate = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )

        #expect(fetchedSession?.notes == "Updated notes")
        #expect(pbAfterUpdate?.id == pbBeforeUpdate?.id)
        #expect(pbAfterUpdate?.weight == pbBeforeUpdate?.weight)
        #expect(pbAfterUpdate?.reps == pbBeforeUpdate?.reps)
    }

    @Test
    func testAddExercisesToExistingSessionPersistsEntriesWithoutTouchingSession() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let benchId = seedExerciseId(named: "Bench Press 3x5")

        let sessionDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let session = makeSession(date: sessionDate)
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )

        let synced = Date().addingTimeInterval(-120)
        session.updatedAt = synced
        session.syncedAt = synced
        try test.performanceDataAccess.persistChanges()
        let originalUpdatedAt = session.updatedAt

        let addedEntry = makeEntry(sessionId: session.id, exerciseId: benchId)
        let addedSet = makeSet(exerciseEntryId: addedEntry.id, weight: 60.0, reps: 5)
        let result = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [addedSet]]
        )

        let storedEntries = try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
        #expect(storedEntries.count == 2)
        #expect(try test.performanceDataAccess.fetchSets(exerciseEntryId: addedEntry.id).count == 1)
        #expect(session.date == sessionDate)
        #expect(session.updatedAt == originalUpdatedAt)
        #expect(session.notes == nil)
        #expect(SyncDirtiness.isDirty(updatedAt: session.updatedAt, syncedAt: session.syncedAt) == false)
        #expect(SyncDirtiness.isDirty(updatedAt: addedEntry.updatedAt, syncedAt: addedEntry.syncedAt))
        #expect(SyncDirtiness.isDirty(updatedAt: addedSet.updatedAt, syncedAt: addedSet.syncedAt))
        #expect(result.newPBs.contains(where: { $0.exerciseId == benchId }))
    }

    @Test
    func testAddExercisesRefusesTombstonedAndForeignSessions() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        _ = try test.memberPerformance.saveSession(session, entries: [], sets: [:])

        let liveEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        let liveSet = makeSet(exerciseEntryId: liveEntry.id, weight: 90.0, reps: 5)
        #expect(throws: MemberPerformanceError.sessionNotFound(session.id)) {
            _ = try test.memberPerformance.addExercisesToSession(
                sessionId: session.id,
                memberId: UUID(),
                entries: [liveEntry],
                sets: [liveEntry.id: [liveSet]]
            )
        }

        session.deletedAt = Date()
        try test.performanceDataAccess.persistChanges()

        let tombstoneEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        #expect(throws: MemberPerformanceError.sessionNotFound(session.id)) {
            _ = try test.memberPerformance.addExercisesToSession(
                sessionId: session.id,
                memberId: testMemberId,
                entries: [tombstoneEntry],
                sets: [tombstoneEntry.id: [makeSet(exerciseEntryId: tombstoneEntry.id, weight: 90.0, reps: 5)]]
            )
        }
        #expect(try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id).isEmpty)
    }

    @Test
    func testAddExercisesBeforeResetDoesNotBecomeCurrentPB() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let oldDate = calendar.date(byAdding: .day, value: -10, to: Date())!

        let session = makeSession(date: oldDate)
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )

        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: squatId)

        let addedEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        let result = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [makeSet(exerciseEntryId: addedEntry.id, weight: 130.0, reps: 5)]]
        )

        #expect(result.newPBs.isEmpty)
        let derived = try test.memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: squatId
        )
        #expect(derived.currentPB == nil)
        #expect(derived.lifetimePB?.weight == 130)
    }

    @Test
    func testAddExercisesSameDayAfterResetBecomesCurrentPB() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )

        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: squatId)
        let reset = try test.performanceDataAccess.fetchExerciseReset(
            memberId: testMemberId,
            exerciseId: squatId
        )
        reset?.updatedAt = Date().addingTimeInterval(-2)
        try test.performanceDataAccess.persistChanges()

        let addedEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        let result = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [makeSet(exerciseEntryId: addedEntry.id, weight: 130.0, reps: 5)]]
        )

        #expect(result.newPBs.contains(where: { $0.weight == 130 }))
        let derived = try test.memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: squatId
        )
        #expect(derived.currentPB?.weight == 130)
        #expect(derived.lifetimePB?.weight == 130)
    }

    @Test
    func testAddExercisesSameDayBeforeResetDoesNotBecomeCurrentPB() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )

        let addedEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [makeSet(exerciseEntryId: addedEntry.id, weight: 130.0, reps: 5)]]
        )

        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: squatId)

        let derived = try test.memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: squatId
        )
        #expect(derived.currentPB == nil)
        #expect(derived.lifetimePB?.weight == 130)
    }

    // MARK: -- Manual PB Entry

    @Test
    func testTC_MP9_RecordAManualPBWithNoExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 80.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )

        #expect(result.isNewPB == true)
        #expect(result.personalBest != nil)
        #expect(result.personalBest?.entryType == .manualEntry)
        #expect(result.personalBest?.setId == nil)
        #expect(
            Calendar.current.isDate(result.personalBest!.achievedAt!, inSameDayAs: Date()),
            "Expected achievedAt to be today's date"
        )
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )?.id == result.personalBest?.id)
    }

    @Test
    func testTC_MP10_RecordAManualPBThatBeatsExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let oldPB = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5
        )

        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 85.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )

        #expect(result.isNewPB == true)

        let allPBs = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(allPBs.count == 2)
        #expect(allPBs.contains { $0.id == oldPB.id })
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )?.id == result.personalBest?.id)
    }

    @Test
    func testTC_MP11_RecordAManualPBThatDoesNotBeatExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let existingPB = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5
        )

        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 75.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )

        #expect(result.isNewPB == false)
        #expect(result.personalBest == nil)

        let currentPB = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(currentPB?.id == existingPB.id)
        #expect(currentPB?.weight == 80.0)
    }

    @Test
    func testTC_MP12_RejectManualPBWithMissingRequiredFields() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        #expect(throws: MemberPerformanceError.invalidMeasurementFields(.weightAndReps)) {
            _ = try test.memberPerformance.recordManualPB(
                exerciseId: freeSquatId,
                memberId: testMemberId,
                weight: 80.0,
                reps: nil,
                time: nil,
                distance: nil,
                achievedAt: Date()
            )
        }
    }

    @Test
    func testTC_MP13_ManualPBAndSessionDerivedPBCoexistInHistory() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        _ = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 80.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)

        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        let allPBs = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        #expect(allPBs.count == 1)
        #expect(allPBs.first?.entryType == .manualEntry)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )?.weight == 85.0)
    }

    // MARK: -- Progression Views

    @Test
    func testTC_MP14_CurrentPBsReturnsOnlyPbExerciseExercises() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let conditioningExercise = ExerciseModel(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!,
            name: "Conditioning Test",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 200
        )
        test.context.insert(conditioningExercise)
        try test.context.save()

        try seedSetForDerivation(
            test: test,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5
        )
        try seedSetForDerivation(
            test: test,
            exerciseId: conditioningExercise.id,
            time: 90.0
        )

        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)

        #expect(currentPBs.count == 1)
        #expect(currentPBs.first?.exerciseId == freeSquatId)
    }

    @Test
    func testTC_MP15_CurrentPBsReturnsOneRecordPerExercise() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        try seedSetForDerivation(
            test: test,
            exerciseId: freeSquatId,
            weight: 70.0,
            reps: 5,
            achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try seedSetForDerivation(
            test: test,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5,
            achievedAt: Date(timeIntervalSince1970: 1_700_086_400)
        )

        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)

        #expect(currentPBs.count == 1)
        #expect(currentPBs.first?.weight == 80.0)
    }

    @Test
    func testTC_MP16_CurrentPBsReturnsResultsOrderedByExerciseDisplayOrder() throws {
        let test = try makeMemberPerformance()
        let overheadPressId = seedExerciseId(named: "Overhead Press")
        let freeSquatId = seedExerciseId(named: "Free Squat")

        try seedSetForDerivation(
            test: test,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5
        )
        try seedSetForDerivation(
            test: test,
            exerciseId: overheadPressId,
            weight: 50.0,
            reps: 5
        )

        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)

        #expect(currentPBs.count == 2)
        #expect(currentPBs[0].exerciseId == overheadPressId)
        #expect(currentPBs[1].exerciseId == freeSquatId)
    }

    private func seedSetForDerivation(
        test: TestContext,
        exerciseId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil,
        achievedAt: Date = Date()
    ) throws {
        let session = SessionModel(memberId: testMemberId, date: achievedAt)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exerciseId)
        let set = ModelSet(
            exerciseEntryId: entry.id,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )
        test.context.insert(session)
        test.context.insert(entry)
        test.context.insert(set)
        try test.context.save()
    }

    @Test
    func testTC_MP17_PbProgressionReturnsHistoryWithinTheDateWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()

        let eightMonthsAgo = calendar.date(byAdding: .month, value: -8, to: now)!
        let fiveMonthsAgo = calendar.date(byAdding: .month, value: -5, to: now)!
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!

        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 70.0,
            reps: 5,
            achievedAt: eightMonthsAgo
        )
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 75.0,
            reps: 5,
            achievedAt: fiveMonthsAgo
        )
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5,
            achievedAt: oneMonthAgo
        )

        let progression = try test.memberPerformance.pbProgression(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: sixMonthsAgo
        )

        #expect(progression.count == 2)
        #expect(progression.map(\.weight) == [75.0, 80.0])
        let dates = progression.compactMap(\.achievedAt)
        #expect(dates == dates.sorted())
    }

    @Test
    func testTC_MP18_PbProgressionReturnsEmptyWhenNoPBsInWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()

        let eightMonthsAgo = calendar.date(byAdding: .month, value: -8, to: now)!
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!

        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5,
            achievedAt: eightMonthsAgo
        )

        let progression = try test.memberPerformance.pbProgression(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: sixMonthsAgo
        )

        #expect(progression.isEmpty)
    }

    @Test
    func testTC_MP19_SessionConsistencyReturnsWeeklyCountsIncludingZeroWeeks() throws {
        let test = try makeMemberPerformance()
        let calendar = mondayCalendar()

        let week1Monday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let week1Wednesday = calendar.date(byAdding: .day, value: 2, to: week1Monday)!
        let week3Tuesday = calendar.date(byAdding: .day, value: 16, to: week1Monday)!
        let week2Monday = calendar.date(byAdding: .day, value: 7, to: week1Monday)!
        let week3Monday = calendar.date(byAdding: .day, value: 14, to: week1Monday)!

        try test.performanceDataAccess.saveSession(makeSession(date: week1Monday))
        try test.performanceDataAccess.saveSession(makeSession(date: week1Wednesday))
        try test.performanceDataAccess.saveSession(makeSession(date: week3Tuesday))

        let consistency = try test.memberPerformance.sessionConsistency(
            memberId: testMemberId,
            from: week1Monday
        )

        let week1 = consistency.first {
            calendar.isDate($0.weekStarting, inSameDayAs: week1Monday)
        }
        let week2 = consistency.first {
            calendar.isDate($0.weekStarting, inSameDayAs: week2Monday)
        }
        let week3 = consistency.first {
            calendar.isDate($0.weekStarting, inSameDayAs: week3Monday)
        }

        #expect(week1 != nil)
        #expect(week2 != nil)
        #expect(week3 != nil)
        #expect(week1?.count == 2)
        #expect(week2?.count == 0)
        #expect(week3?.count == 1)
    }

    @Test
    func testTC_MP20_SessionConsistencyWeeksAlwaysStartOnMonday() throws {
        let test = try makeMemberPerformance()
        let calendar = mondayCalendar()
        let from = calendar.date(byAdding: .month, value: -2, to: Date())!

        let consistency = try test.memberPerformance.sessionConsistency(
            memberId: testMemberId,
            from: from
        )

        #expect(!consistency.isEmpty)
        for week in consistency {
            let weekday = calendar.component(.weekday, from: week.weekStarting)
            #expect(weekday == 2, "Expected Monday, got weekday \(weekday) for \(week.weekStarting)")
        }
    }

    // MARK: -- Exercise History

    @Test
    func testTC_MP21_ExerciseHistoryReturnsOneEntryPerSession() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        let earlierDate = calendar.date(byAdding: .day, value: -10, to: now)!
        let laterDate = calendar.date(byAdding: .day, value: -5, to: now)!
        let from = calendar.date(byAdding: .month, value: -6, to: now)!

        let earlierSession = makeSession(date: earlierDate)
        let earlierEntry = makeEntry(sessionId: earlierSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            earlierSession,
            entries: [earlierEntry],
            sets: [earlierEntry.id: [makeSet(exerciseEntryId: earlierEntry.id, weight: 80.0, reps: 5)]]
        )

        let laterSession = makeSession(date: laterDate)
        let laterEntry = makeEntry(sessionId: laterSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            laterSession,
            entries: [laterEntry],
            sets: [laterEntry.id: [makeSet(exerciseEntryId: laterEntry.id, weight: 82.0, reps: 5)]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: from
        )

        #expect(history.count == 2)
        #expect(history[0].sessionDate == earlierDate)
        #expect(history[1].sessionDate == laterDate)
        #expect(history.map(\.sessionDate) == history.map(\.sessionDate).sorted())
    }

    @Test
    func testTC_MP22_ExerciseHistorySelectsBestSetWhenMultipleSetsLogged() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .month, value: -6, to: Date())!

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [
                entry.id: [
                    makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5),
                    makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
                ]
            ]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: from
        )

        #expect(history.count == 1)
        #expect(history[0].set.weight == 85.0)
        #expect(history[0].set.reps == 5)
    }

    @Test
    func testTC_MP23_ExerciseHistoryMarksPBSetsCorrectly() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .month, value: -6, to: Date())!

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: from
        )

        #expect(history.count == 1)
        #expect(history[0].isPB == true)
        #expect(history[0].set.id == set.id)
    }

    @Test
    func testTC_MP24_ExerciseHistoryExcludesSessionsOutsideTheDateWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        let eightMonthsAgo = calendar.date(byAdding: .month, value: -8, to: now)!
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!

        let oldSession = makeSession(date: eightMonthsAgo)
        let oldEntry = makeEntry(sessionId: oldSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            oldSession,
            entries: [oldEntry],
            sets: [oldEntry.id: [makeSet(exerciseEntryId: oldEntry.id, weight: 75.0, reps: 5)]]
        )

        let recentSession = makeSession(date: twoMonthsAgo)
        let recentEntry = makeEntry(sessionId: recentSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            recentSession,
            entries: [recentEntry],
            sets: [recentEntry.id: [makeSet(exerciseEntryId: recentEntry.id, weight: 80.0, reps: 5)]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: sixMonthsAgo
        )

        #expect(history.count == 1)
        #expect(history[0].sessionDate == twoMonthsAgo)
        #expect(history[0].set.weight == 80.0)
    }

    @Test
    func testTC_MP25_ExerciseHistoryReturnsEmptyWhenNoSessionsInWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        let eightMonthsAgo = calendar.date(byAdding: .month, value: -8, to: now)!
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!

        let oldSession = makeSession(date: eightMonthsAgo)
        let oldEntry = makeEntry(sessionId: oldSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            oldSession,
            entries: [oldEntry],
            sets: [oldEntry.id: [makeSet(exerciseEntryId: oldEntry.id, weight: 75.0, reps: 5)]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: sixMonthsAgo
        )

        #expect(history.isEmpty)
    }

    // MARK: -- Session Deletion

    @Test
    func testTC_MP26_DeleteSessionWithNoPBsRemovesSessionAndEntries() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 100.0,
            reps: 5
        )
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 90.0, reps: 5)]]
        )

        try test.memberPerformance.deleteSession(id: session.id, memberId: testMemberId)

        let stored = try test.performanceDataAccess.fetchSession(id: session.id)
        #expect(stored != nil)
        #expect(stored?.deletedAt != nil)
        let entries = try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
        #expect(entries.count == 1)
        #expect(entries.first?.deletedAt != nil)
        let sets = try test.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
        #expect(sets.count == 1)
        #expect(sets.first?.deletedAt != nil)
        #expect(try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: Date.distantPast
        ).isEmpty)
        let weeks = try test.memberPerformance.sessionConsistency(
            memberId: testMemberId,
            from: Calendar.current.startOfDay(for: Date())
        )
        #expect(weeks.allSatisfy { $0.count == 0 })
    }

    @Test
    func testTC_MP27_DeleteSessionContainingPBRemovesPBWhenNoHistory() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        try test.memberPerformance.deleteSession(id: session.id, memberId: testMemberId)

        let stored = try test.performanceDataAccess.fetchSession(id: session.id)
        #expect(stored != nil)
        #expect(stored?.deletedAt != nil)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
        #expect(try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId).isEmpty)
    }

    @Test
    func testDeleteSessionTombstoneIsDirtyForPush() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 90.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )
        let syncedAt = Date().addingTimeInterval(-60)
        session.syncedAt = syncedAt
        entry.syncedAt = syncedAt
        set.syncedAt = syncedAt
        try test.performanceDataAccess.persistChanges()

        try test.memberPerformance.deleteSession(id: session.id, memberId: testMemberId)

        #expect(SyncDirtiness.isDirty(updatedAt: session.updatedAt, syncedAt: session.syncedAt))
        #expect(SyncDirtiness.isDirty(updatedAt: entry.updatedAt, syncedAt: entry.syncedAt))
        #expect(SyncDirtiness.isDirty(updatedAt: set.updatedAt, syncedAt: set.syncedAt))
        let local = SwiftDataSyncLocalDataAccess(context: test.context)
        let dirtySessions = try local.fetchDirtySessions(memberId: testMemberId)
        #expect(dirtySessions.contains(where: { $0.id == session.id }))
        let row = SyncPayloadMapper.sessionRow(
            session,
            gymId: UUID(),
            deviceId: UUID(),
            syncedAt: Date()
        )
        #expect(row["deleted_at"] is String)
    }

    @Test
    func testCloudSessionTombstoneHidesLiveChildrenOnSecondDevicePull() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )?.weight == 85.0)

        let deletedAt = Date().addingTimeInterval(10)
        let remote = CloudSessionRow(
            id: session.id,
            gymId: UUID(),
            memberId: testMemberId,
            date: session.date,
            notes: session.notes,
            caloriesBurned: session.caloriesBurned,
            createdAt: session.createdAt,
            updatedAt: deletedAt,
            syncedAt: deletedAt,
            deletedAt: deletedAt,
            sourceDeviceId: nil
        )
        let outcome = try SyncRecordMerger.mergeSession(
            remote,
            localDataAccess: SwiftDataSyncLocalDataAccess(context: test.context)
        )
        #expect(outcome == .cloudWon)
        #expect(session.deletedAt != nil)
        #expect(try test.performanceDataAccess.fetchSets(exerciseEntryId: entry.id).first?.deletedAt == nil)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
    }

    @Test
    func testCloudSessionTombstoneInsertOnReinstallDoesNotResurrectAsLive() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let sessionId = UUID()
        let deletedAt = Date()
        let remote = CloudSessionRow(
            id: sessionId,
            gymId: UUID(),
            memberId: testMemberId,
            date: Date(),
            notes: nil,
            caloriesBurned: nil,
            createdAt: deletedAt,
            updatedAt: deletedAt,
            syncedAt: deletedAt,
            deletedAt: deletedAt,
            sourceDeviceId: nil
        )
        let outcome = try SyncRecordMerger.mergeSession(
            remote,
            localDataAccess: SwiftDataSyncLocalDataAccess(context: test.context)
        )
        #expect(outcome == .inserted)
        let stored = try test.performanceDataAccess.fetchSession(id: sessionId)
        #expect(stored?.deletedAt != nil)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
    }

    @Test
    func testWebOriginatedCascadedSessionTombstoneHidesOnPull() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )?.weight == 85.0)

        let deletedAt = Date().addingTimeInterval(10)
        let gymId = UUID()
        let local = SwiftDataSyncLocalDataAccess(context: test.context)

        let sessionOutcome = try SyncRecordMerger.mergeSession(
            CloudSessionRow(
                id: session.id,
                gymId: gymId,
                memberId: testMemberId,
                date: session.date,
                notes: session.notes,
                caloriesBurned: session.caloriesBurned,
                createdAt: session.createdAt,
                updatedAt: deletedAt,
                syncedAt: deletedAt,
                deletedAt: deletedAt,
                sourceDeviceId: nil
            ),
            localDataAccess: local
        )
        let entryOutcome = try SyncRecordMerger.mergeExerciseEntry(
            CloudExerciseEntryRow(
                id: entry.id,
                gymId: gymId,
                sessionId: session.id,
                exerciseId: freeSquatId,
                createdAt: entry.createdAt,
                updatedAt: deletedAt,
                syncedAt: deletedAt,
                deletedAt: deletedAt,
                sourceDeviceId: nil
            ),
            localDataAccess: local
        )
        let setOutcome = try SyncRecordMerger.mergeSet(
            CloudSetRow(
                id: set.id,
                gymId: gymId,
                exerciseEntryId: entry.id,
                weight: set.weight,
                reps: set.reps,
                timeSeconds: set.time,
                distance: set.distance,
                createdAt: set.createdAt,
                updatedAt: deletedAt,
                syncedAt: deletedAt,
                deletedAt: deletedAt,
                sourceDeviceId: nil
            ),
            localDataAccess: local
        )

        #expect(sessionOutcome == .cloudWon)
        #expect(entryOutcome == .cloudWon)
        #expect(setOutcome == .cloudWon)
        #expect(session.deletedAt != nil)
        #expect(entry.deletedAt != nil)
        #expect(set.deletedAt != nil)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
        #expect(try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: Date.distantPast
        ).isEmpty)
    }

    @Test
    func testWebOriginatedManualPBEditReachesIOSOnPull() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let undated = PersonalBestModel(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            weight: 100,
            reps: 5,
            achievedAt: nil,
            entryType: .manualEntry
        )
        try test.performanceDataAccess.savePersonalBest(undated)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)

        let dated = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let updatedAt = Date().addingTimeInterval(10)
        let outcome = try SyncRecordMerger.mergePersonalBest(
            CloudPersonalBestRow(
                id: undated.id,
                gymId: UUID(),
                memberId: testMemberId,
                exerciseId: freeSquatId,
                setId: nil,
                weight: 110,
                reps: 5,
                timeSeconds: nil,
                distance: nil,
                achievedAt: dated,
                entryType: PBEntryType.manualEntry.rawValue,
                createdAt: undated.createdAt,
                updatedAt: updatedAt,
                syncedAt: updatedAt,
                deletedAt: nil,
                sourceDeviceId: nil
            ),
            localDataAccess: SwiftDataSyncLocalDataAccess(context: test.context)
        )

        #expect(outcome == .cloudWon)
        #expect(undated.weight == 110)
        #expect(undated.achievedAt != nil)
        let current = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(current?.id == undated.id)
        #expect(current?.weight == 110)
    }

    // MARK: -- PB Management

    @Test
    func testTC_MP29_ResetCurrentPBCreatesExerciseResetAndClearsDerivedCurrent() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        try seedSetForDerivation(
            test: test,
            exerciseId: freeSquatId,
            weight: 85.0,
            reps: 5
        )
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )?.weight == 85.0)

        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: freeSquatId)

        let reset = try test.performanceDataAccess.fetchExerciseReset(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(reset != nil)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
    }

    @Test
    func testTC_MP30_ResetCurrentPBHasNoEffectWhenNoCurrentPBExists() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: freeSquatId)

        #expect(try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        ).isEmpty)
        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
    }

    @Test
    func testTC_MP31_DeletePersonalBestRemovesTheRecord() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let pb = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 85.0,
            reps: 5
        )

        try test.memberPerformance.deletePersonalBest(
            id: pb.id,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        let remaining = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(remaining.count == 1)
        #expect(remaining.first?.deletedAt != nil)
    }

    @Test
    func testUpdateManualPBChangesValuesAndDateInPlace() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let undated = PersonalBestModel(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            weight: 100,
            reps: 5,
            achievedAt: nil,
            entryType: .manualEntry
        )
        try test.performanceDataAccess.savePersonalBest(undated)

        let dated = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        try test.memberPerformance.updateManualPB(
            id: undated.id,
            memberId: testMemberId,
            exerciseId: freeSquatId,
            weight: 110,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: dated
        )

        let updated = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        ).first
        #expect(updated?.weight == 110)
        #expect(updated?.reps == 5)
        #expect(updated?.achievedAt != nil)

        let current = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(current?.weight == 110)
    }

    @Test
    func testTC_MP33_DeletePersonalBestLeavesNoCurrentPBWhenDeletingOnlyRecord() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let pb = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 85.0,
            reps: 5
        )

        try test.memberPerformance.deletePersonalBest(
            id: pb.id,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
        let remaining = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(remaining.count == 1)
        #expect(remaining.first?.deletedAt != nil)
    }

    // MARK: -- History entry deletion

    @Test
    func testTC_MP34_DeleteNonPBSessionSetRemovesSetOnly() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 100,
            reps: 5
        )

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        try test.memberPerformance.deleteHistoryEntry(
            setId: set.id,
            personalBestId: nil,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        #expect(try test.performanceDataAccess.fetchSession(id: session.id) != nil)
        #expect(try test.performanceDataAccess.fetchSession(id: session.id)?.deletedAt == nil)
        let sets = try test.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
        #expect(sets.count == 1)
        #expect(sets.first?.deletedAt != nil)
        let currentPB = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(currentPB?.weight == 100)
    }

    @Test
    func testTC_MP35_DeleteSessionDerivedPBRemovesSetAndRestoresPreviousPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let earlier = calendar.date(byAdding: .day, value: -10, to: Date())!
        let later = calendar.date(byAdding: .day, value: -5, to: Date())!

        let earlierSession = makeSession(date: earlier)
        let earlierEntry = makeEntry(sessionId: earlierSession.id, exerciseId: freeSquatId)
        let earlierSet = makeSet(exerciseEntryId: earlierEntry.id, weight: 80.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            earlierSession,
            entries: [earlierEntry],
            sets: [earlierEntry.id: [earlierSet]]
        )

        let laterSession = makeSession(date: later)
        let laterEntry = makeEntry(sessionId: laterSession.id, exerciseId: freeSquatId)
        let laterSet = makeSet(exerciseEntryId: laterEntry.id, weight: 85.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            laterSession,
            entries: [laterEntry],
            sets: [laterEntry.id: [laterSet]]
        )

        let currentPB = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(currentPB?.setId == laterSet.id)

        try test.memberPerformance.deleteHistoryEntry(
            setId: laterSet.id,
            personalBestId: nil,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        let laterSets = try test.performanceDataAccess.fetchSets(exerciseEntryId: laterEntry.id)
        #expect(laterSets.count == 1)
        #expect(laterSets.first?.deletedAt != nil)
        let restoredPB = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(restoredPB?.setId == earlierSet.id)
        #expect(restoredPB?.weight == 80.0)
    }

    @Test
    func testTC_MP36_DeleteManualPBViaHistoryEntryRemovesPBRecord() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let manualPB = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 85.0,
            reps: 5,
            entryType: .manualEntry
        )

        try test.memberPerformance.deleteHistoryEntry(
            setId: nil,
            personalBestId: manualPB.id,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        #expect(try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        ) == nil)
        let remaining = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(remaining.count == 1)
        #expect(remaining.first?.deletedAt != nil)
    }

    @Test
    func testTC_MP37_DeleteCurrentSessionPBRestoresPreviousForBoard() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let earlier = calendar.date(byAdding: .day, value: -10, to: Date())!
        let later = calendar.date(byAdding: .day, value: -5, to: Date())!

        let earlierSession = makeSession(date: earlier)
        let earlierEntry = makeEntry(sessionId: earlierSession.id, exerciseId: freeSquatId)
        let earlierSet = makeSet(exerciseEntryId: earlierEntry.id, weight: 80.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            earlierSession,
            entries: [earlierEntry],
            sets: [earlierEntry.id: [earlierSet]]
        )

        let laterSession = makeSession(date: later)
        let laterEntry = makeEntry(sessionId: laterSession.id, exerciseId: freeSquatId)
        let laterSet = makeSet(exerciseEntryId: laterEntry.id, weight: 100.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            laterSession,
            entries: [laterEntry],
            sets: [laterEntry.id: [laterSet]]
        )

        let currentPB = try derivedCurrentPB(
            memberPerformance: test.memberPerformance,
            exerciseId: freeSquatId
        )
        #expect(currentPB?.setId == laterSet.id)

        try test.memberPerformance.deleteHistoryEntry(
            setId: laterSet.id,
            personalBestId: nil,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        let boardPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)
        let restored = boardPBs.first { $0.exerciseId == freeSquatId }
        #expect(restored?.weight == 80.0)
        #expect(restored?.setId == earlierSet.id)
    }

    @Test
    func testTC_MP38_DeleteCurrentManualPBRestoresPreviousForBoard() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let historical = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5,
            achievedAt: Date().addingTimeInterval(-86_400)
        )
        let current = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 100.0,
            reps: 5
        )

        try test.memberPerformance.deleteHistoryEntry(
            setId: nil,
            personalBestId: current.id,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        let boardPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)
        let restored = boardPBs.first { $0.exerciseId == freeSquatId }
        #expect(restored?.id == historical.id)
        #expect(restored?.weight == 80.0)
    }

    @Test
    func testTC_MP43_ManualPBUsesSpecifiedDateNotToday() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let specifiedDate = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!

        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 80.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: specifiedDate
        )

        #expect(result.isNewPB == true)
        #expect(calendar.isDate(result.personalBest!.achievedAt!, inSameDayAs: specifiedDate))
        #expect(!calendar.isDate(result.personalBest!.achievedAt!, inSameDayAs: Date()))
    }

    @Test
    func testTC_MP43b_UndatedManualPBStoresNilAchievedAt() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 90.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: nil
        )

        #expect(result.isNewPB == true)
        #expect(result.personalBest?.achievedAt == nil)
        let derived = try test.memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(derived.currentPB == nil, "Undated manuals are never current")
        #expect(derived.lifetimePB?.id == result.personalBest?.id)
    }

    @Test
    func testTC_MP44_ManualPBWithPastDateAppearsInProgressionHistory() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)!

        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 80.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: sixMonthsAgo
        )

        let progression = try test.memberPerformance.pbProgression(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: oneYearAgo
        )

        #expect(progression.count == 1)
        #expect(progression[0].id == result.personalBest!.id)
        #expect(calendar.isDate(progression[0].achievedAt!, inSameDayAs: sixMonthsAgo))
    }
}

#else
import Foundation
import XCTest
import SwiftData
@testable import GymPerformance

final class MemberPerformanceTests: XCTestCase {

    private let testMemberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    private struct TestContext {
        let memberPerformance: DefaultMemberPerformance
        let performanceDataAccess: SwiftDataPerformanceDataAccess
        let exerciseRegistry: DefaultExerciseRegistry
        let context: ModelContext
    }

    private func makeMemberPerformance() throws -> TestContext {
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
            exerciseRegistry: exerciseRegistry,
            context: context
        )
    }

    private func seedExerciseId(named name: String) -> UUID {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise: \(name)")
        }
        return exercise.id
    }

    private func makeSession(date: Date = Date()) -> SessionModel {
        SessionModel(memberId: testMemberId, date: date)
    }

    private func makeEntry(sessionId: UUID, exerciseId: UUID) -> ExerciseEntryModel {
        ExerciseEntryModel(sessionId: sessionId, exerciseId: exerciseId)
    }

    private func makeSet(
        exerciseEntryId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil
    ) -> ModelSet {
        ModelSet(
            exerciseEntryId: exerciseEntryId,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )
    }

    private func saveExistingPB(
        performanceDataAccess: SwiftDataPerformanceDataAccess,
        exerciseId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil,
        achievedAt: Date = Date(),
        entryType: PBEntryType = .manualEntry
    ) throws -> PersonalBestModel {
        let pb = PersonalBestModel(
            memberId: testMemberId,
            exerciseId: exerciseId,
            setId: nil,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance,
            achievedAt: achievedAt,
            entryType: entryType
        )
        try performanceDataAccess.savePersonalBest(pb)
        return pb
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

    private func seedSetForDerivation(
        test: TestContext,
        exerciseId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil,
        achievedAt: Date = Date()
    ) throws {
        let session = SessionModel(memberId: testMemberId, date: achievedAt)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exerciseId)
        let set = ModelSet(
            exerciseEntryId: entry.id,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )
        test.context.insert(session)
        test.context.insert(entry)
        test.context.insert(set)
        try test.context.save()
    }

    private func mondayCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    func testTC_MP1_SaveAValidSessionWithOneExerciseAndOneSet() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5)

        let result = try test.memberPerformance.saveSession(session, entries: [entry], sets: [entry.id: [set]])

        XCTAssertNotNil(try test.performanceDataAccess.fetchSession(id: session.id))
        XCTAssertEqual(result.newPBs.count, 1)
        XCTAssertEqual(result.newPBs.first?.entryType, .sessionDerived)
    }

    func testTC_MP2_SaveASessionWhereNoPBIsAchieved() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 100.0, reps: 5)

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 90.0, reps: 5)]]
        )

        XCTAssertTrue(result.newPBs.isEmpty)
        XCTAssertEqual(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId)?.weight, 100.0)
    }

    func testTC_MP3_SaveASessionThatBeatsAnExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let earlierSession = makeSession(date: Date().addingTimeInterval(-86_400))
        let earlierEntry = makeEntry(sessionId: earlierSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            earlierSession,
            entries: [earlierEntry],
            sets: [earlierEntry.id: [makeSet(exerciseEntryId: earlierEntry.id, weight: 80.0, reps: 5)]]
        )

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        XCTAssertEqual(result.newPBs.count, 1)
        XCTAssertEqual(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId)?.weight, 85.0)
        XCTAssertEqual(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId)?.setId, set.id)
        XCTAssertTrue(try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId).isEmpty)
    }

    func testTC_MP4_SaveASessionWithMultipleExercisesMultiplePBs() throws {
        let test = try makeMemberPerformance()
        let session = makeSession()
        let squatEntry = makeEntry(sessionId: session.id, exerciseId: seedExerciseId(named: "Free Squat"))
        let pressEntry = makeEntry(sessionId: session.id, exerciseId: seedExerciseId(named: "Overhead Press"))
        let result = try test.memberPerformance.saveSession(
            session,
            entries: [squatEntry, pressEntry],
            sets: [
                squatEntry.id: [makeSet(exerciseEntryId: squatEntry.id, weight: 80.0, reps: 5)],
                pressEntry.id: [makeSet(exerciseEntryId: pressEntry.id, weight: 50.0, reps: 5)]
            ]
        )
        XCTAssertEqual(result.newPBs.count, 2)
    }

    func testTC_MP5_SaveASessionWithAConditioningExerciseNoPBEvaluated() throws {
        let test = try makeMemberPerformance()
        let conditioningExercise = ExerciseModel(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            name: "400m Run",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 100
        )
        test.context.insert(conditioningExercise)
        try test.context.save()

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: conditioningExercise.id)
        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, time: 92.0)]]
        )
        XCTAssertTrue(result.newPBs.isEmpty)
    }

    func testTC_MP6_SaveASessionWithNoExerciseEntriesAsAttendanceRecord() throws {
        let test = try makeMemberPerformance()
        let session = makeSession()
        session.notes = "Attendance only"

        let result = try test.memberPerformance.saveSession(session, entries: [], sets: [:])

        XCTAssertTrue(result.newPBs.isEmpty)
        XCTAssertNotNil(try test.performanceDataAccess.fetchSession(id: session.id))
        XCTAssertTrue(try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id).isEmpty)
    }

    func testTC_MP7_RejectASetWithMissingRequiredMeasurementFields() throws {
        let test = try makeMemberPerformance()
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: seedExerciseId(named: "Free Squat"))
        XCTAssertThrowsError(
            try test.memberPerformance.saveSession(
                session,
                entries: [entry],
                sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: nil)]]
            )
        )
    }

    func testTC_MP8_UpdateASessionDoesNotReEvaluatePBs() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5)]]
        )
        let pbBefore = try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId)
        session.notes = "Updated notes"
        try test.memberPerformance.updateSession(session)
        let pbAfter = try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId)
        XCTAssertEqual(pbAfter?.setId, pbBefore?.setId)
    }

    func testAddExercisesToExistingSessionPersistsEntriesWithoutTouchingSession() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let benchId = seedExerciseId(named: "Bench Press 3x5")
        let sessionDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let session = makeSession(date: sessionDate)
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )
        let synced = Date().addingTimeInterval(-120)
        session.updatedAt = synced
        session.syncedAt = synced
        try test.performanceDataAccess.persistChanges()
        let originalUpdatedAt = session.updatedAt
        let addedEntry = makeEntry(sessionId: session.id, exerciseId: benchId)
        let addedSet = makeSet(exerciseEntryId: addedEntry.id, weight: 60.0, reps: 5)
        let result = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [addedSet]]
        )
        XCTAssertEqual(try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id).count, 2)
        XCTAssertEqual(session.date, sessionDate)
        XCTAssertEqual(session.updatedAt, originalUpdatedAt)
        XCTAssertFalse(SyncDirtiness.isDirty(updatedAt: session.updatedAt, syncedAt: session.syncedAt))
        XCTAssertTrue(SyncDirtiness.isDirty(updatedAt: addedEntry.updatedAt, syncedAt: addedEntry.syncedAt))
        XCTAssertTrue(result.newPBs.contains(where: { $0.exerciseId == benchId }))
    }

    func testAddExercisesRefusesTombstonedAndForeignSessions() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        _ = try test.memberPerformance.saveSession(session, entries: [], sets: [:])
        let liveEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        XCTAssertThrowsError(
            try test.memberPerformance.addExercisesToSession(
                sessionId: session.id,
                memberId: UUID(),
                entries: [liveEntry],
                sets: [liveEntry.id: [makeSet(exerciseEntryId: liveEntry.id, weight: 90.0, reps: 5)]]
            )
        )
        session.deletedAt = Date()
        try test.performanceDataAccess.persistChanges()
        let tombstoneEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        XCTAssertThrowsError(
            try test.memberPerformance.addExercisesToSession(
                sessionId: session.id,
                memberId: testMemberId,
                entries: [tombstoneEntry],
                sets: [tombstoneEntry.id: [makeSet(exerciseEntryId: tombstoneEntry.id, weight: 90.0, reps: 5)]]
            )
        )
        XCTAssertTrue(try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id).isEmpty)
    }

    func testAddExercisesBeforeResetDoesNotBecomeCurrentPB() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let session = makeSession(date: oldDate)
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )
        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: squatId)
        let addedEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        let result = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [makeSet(exerciseEntryId: addedEntry.id, weight: 130.0, reps: 5)]]
        )
        XCTAssertTrue(result.newPBs.isEmpty)
        let derived = try test.memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: squatId
        )
        XCTAssertNil(derived.currentPB)
        XCTAssertEqual(derived.lifetimePB?.weight, 130)
    }

    func testAddExercisesSameDayAfterResetBecomesCurrentPB() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )
        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: squatId)
        let reset = try test.performanceDataAccess.fetchExerciseReset(
            memberId: testMemberId,
            exerciseId: squatId
        )
        reset?.updatedAt = Date().addingTimeInterval(-2)
        try test.performanceDataAccess.persistChanges()
        let addedEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        let result = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [makeSet(exerciseEntryId: addedEntry.id, weight: 130.0, reps: 5)]]
        )
        XCTAssertTrue(result.newPBs.contains(where: { $0.weight == 130 }))
        let derived = try test.memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: squatId
        )
        XCTAssertEqual(derived.currentPB?.weight, 130)
        XCTAssertEqual(derived.lifetimePB?.weight, 130)
    }

    func testAddExercisesSameDayBeforeResetDoesNotBecomeCurrentPB() throws {
        let test = try makeMemberPerformance()
        let squatId = seedExerciseId(named: "Free Squat")
        let session = makeSession()
        let originalEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [originalEntry],
            sets: [originalEntry.id: [makeSet(exerciseEntryId: originalEntry.id, weight: 80.0, reps: 5)]]
        )
        let addedEntry = makeEntry(sessionId: session.id, exerciseId: squatId)
        _ = try test.memberPerformance.addExercisesToSession(
            sessionId: session.id,
            memberId: testMemberId,
            entries: [addedEntry],
            sets: [addedEntry.id: [makeSet(exerciseEntryId: addedEntry.id, weight: 130.0, reps: 5)]]
        )
        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: squatId)
        let derived = try test.memberPerformance.deriveExerciseReadState(
            memberId: testMemberId,
            exerciseId: squatId
        )
        XCTAssertNil(derived.currentPB)
        XCTAssertEqual(derived.lifetimePB?.weight, 130)
    }

    func testTC_MP9_RecordAManualPBWithNoExistingPB() throws {
        let test = try makeMemberPerformance()
        let result = try test.memberPerformance.recordManualPB(
            exerciseId: seedExerciseId(named: "Free Squat"),
            memberId: testMemberId,
            weight: 80.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )
        XCTAssertTrue(result.isNewPB)
        XCTAssertEqual(result.personalBest?.entryType, .manualEntry)
        XCTAssertNil(result.personalBest?.setId)
    }

    func testTC_MP10_RecordAManualPBThatBeatsExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let oldPB = try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5)
        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 85.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )
        XCTAssertTrue(result.isNewPB)
        XCTAssertEqual(try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId).count, 2)
        XCTAssertEqual(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId)?.id, result.personalBest?.id)
    }

    func testTC_MP11_RecordAManualPBThatDoesNotBeatExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5)
        let result = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 75.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )
        XCTAssertFalse(result.isNewPB)
        XCTAssertNil(result.personalBest)
    }

    func testTC_MP12_RejectManualPBWithMissingRequiredFields() throws {
        let test = try makeMemberPerformance()
        XCTAssertThrowsError(
            try test.memberPerformance.recordManualPB(
                exerciseId: seedExerciseId(named: "Free Squat"),
                memberId: testMemberId,
                weight: 80.0,
                reps: nil,
                time: nil,
                distance: nil,
                achievedAt: Date()
            )
        )
    }

    func testTC_MP13_ManualPBAndSessionDerivedPBCoexistInHistory() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        _ = try test.memberPerformance.recordManualPB(
            exerciseId: freeSquatId,
            memberId: testMemberId,
            weight: 80.0,
            reps: 5,
            time: nil,
            distance: nil,
            achievedAt: Date()
        )
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)]]
        )
        let allPBs = try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId)
        XCTAssertEqual(allPBs.count, 1)
        XCTAssertEqual(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId)?.weight, 85.0)
    }

    func testTC_MP14_CurrentPBsReturnsOnlyPbExerciseExercises() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let conditioningExercise = ExerciseModel(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!,
            name: "Conditioning Test",
            category: .conditioning,
            measurementType: .timeOnly,
            displayOrder: 200
        )
        test.context.insert(conditioningExercise)
        try test.context.save()
        try seedSetForDerivation(test: test, exerciseId: freeSquatId, weight: 80.0, reps: 5)
        try seedSetForDerivation(test: test, exerciseId: conditioningExercise.id, time: 90.0)
        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)
        XCTAssertEqual(currentPBs.count, 1)
    }

    func testTC_MP15_CurrentPBsReturnsOneRecordPerExercise() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        try seedSetForDerivation(
            test: test,
            exerciseId: freeSquatId,
            weight: 70.0,
            reps: 5,
            achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try seedSetForDerivation(
            test: test,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5,
            achievedAt: Date(timeIntervalSince1970: 1_700_086_400)
        )
        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)
        XCTAssertEqual(currentPBs.count, 1)
        XCTAssertEqual(currentPBs.first?.weight, 80.0)
    }

    func testTC_MP16_CurrentPBsReturnsResultsOrderedByExerciseDisplayOrder() throws {
        let test = try makeMemberPerformance()
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: seedExerciseId(named: "Free Squat"), weight: 80.0, reps: 5)
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: seedExerciseId(named: "Overhead Press"), weight: 50.0, reps: 5)
        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)
        XCTAssertEqual(currentPBs[0].exerciseId, seedExerciseId(named: "Overhead Press"))
    }

    func testTC_MP17_PbProgressionReturnsHistoryWithinTheDateWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 70.0, reps: 5, achievedAt: calendar.date(byAdding: .month, value: -8, to: now)!)
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 75.0, reps: 5, achievedAt: calendar.date(byAdding: .month, value: -5, to: now)!)
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5, achievedAt: calendar.date(byAdding: .month, value: -1, to: now)!)
        let progression = try test.memberPerformance.pbProgression(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: calendar.date(byAdding: .month, value: -6, to: now)!
        )
        XCTAssertEqual(progression.count, 2)
    }

    func testTC_MP18_PbProgressionReturnsEmptyWhenNoPBsInWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5, achievedAt: calendar.date(byAdding: .month, value: -8, to: now)!)
        let progression = try test.memberPerformance.pbProgression(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: calendar.date(byAdding: .month, value: -6, to: now)!
        )
        XCTAssertTrue(progression.isEmpty)
    }

    func testTC_MP19_SessionConsistencyReturnsWeeklyCountsIncludingZeroWeeks() throws {
        let test = try makeMemberPerformance()
        let calendar = mondayCalendar()
        let week1Monday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        try test.performanceDataAccess.saveSession(makeSession(date: week1Monday))
        try test.performanceDataAccess.saveSession(makeSession(date: calendar.date(byAdding: .day, value: 2, to: week1Monday)!))
        try test.performanceDataAccess.saveSession(makeSession(date: calendar.date(byAdding: .day, value: 16, to: week1Monday)!))
        let consistency = try test.memberPerformance.sessionConsistency(memberId: testMemberId, from: week1Monday)
        let week2Monday = calendar.date(byAdding: .day, value: 7, to: week1Monday)!
        let week2 = consistency.first { calendar.isDate($0.weekStarting, inSameDayAs: week2Monday) }
        XCTAssertEqual(week2?.count, 0)
    }

    func testTC_MP20_SessionConsistencyWeeksAlwaysStartOnMonday() throws {
        let test = try makeMemberPerformance()
        let calendar = mondayCalendar()
        let consistency = try test.memberPerformance.sessionConsistency(
            memberId: testMemberId,
            from: calendar.date(byAdding: .month, value: -2, to: Date())!
        )
        XCTAssertTrue(consistency.allSatisfy { calendar.component(.weekday, from: $0.weekStarting) == 2 })
    }

    func testTC_MP21_ExerciseHistoryReturnsOneEntryPerSession() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        let earlierDate = calendar.date(byAdding: .day, value: -10, to: now)!
        let laterDate = calendar.date(byAdding: .day, value: -5, to: now)!
        let from = calendar.date(byAdding: .month, value: -6, to: now)!

        let earlierSession = makeSession(date: earlierDate)
        let earlierEntry = makeEntry(sessionId: earlierSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            earlierSession,
            entries: [earlierEntry],
            sets: [earlierEntry.id: [makeSet(exerciseEntryId: earlierEntry.id, weight: 80.0, reps: 5)]]
        )

        let laterSession = makeSession(date: laterDate)
        let laterEntry = makeEntry(sessionId: laterSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            laterSession,
            entries: [laterEntry],
            sets: [laterEntry.id: [makeSet(exerciseEntryId: laterEntry.id, weight: 82.0, reps: 5)]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: from
        )

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].sessionDate, earlierDate)
        XCTAssertEqual(history[1].sessionDate, laterDate)
    }

    func testTC_MP22_ExerciseHistorySelectsBestSetWhenMultipleSetsLogged() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let from = Calendar.current.date(byAdding: .month, value: -6, to: Date())!

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [
                entry.id: [
                    makeSet(exerciseEntryId: entry.id, weight: 80.0, reps: 5),
                    makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
                ]
            ]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: from
        )

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].set.weight, 85.0)
        XCTAssertEqual(history[0].set.reps, 5)
    }

    func testTC_MP23_ExerciseHistoryMarksPBSetsCorrectly() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let from = Calendar.current.date(byAdding: .month, value: -6, to: Date())!

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let set = makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [set]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: from
        )

        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history[0].isPB)
        XCTAssertEqual(history[0].set.id, set.id)
    }

    func testTC_MP24_ExerciseHistoryExcludesSessionsOutsideTheDateWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        let eightMonthsAgo = calendar.date(byAdding: .month, value: -8, to: now)!
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!

        let oldSession = makeSession(date: eightMonthsAgo)
        let oldEntry = makeEntry(sessionId: oldSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            oldSession,
            entries: [oldEntry],
            sets: [oldEntry.id: [makeSet(exerciseEntryId: oldEntry.id, weight: 75.0, reps: 5)]]
        )

        let recentSession = makeSession(date: twoMonthsAgo)
        let recentEntry = makeEntry(sessionId: recentSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            recentSession,
            entries: [recentEntry],
            sets: [recentEntry.id: [makeSet(exerciseEntryId: recentEntry.id, weight: 80.0, reps: 5)]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: sixMonthsAgo
        )

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].sessionDate, twoMonthsAgo)
        XCTAssertEqual(history[0].set.weight, 80.0)
    }

    func testTC_MP25_ExerciseHistoryReturnsEmptyWhenNoSessionsInWindow() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let calendar = Calendar.current
        let now = Date()
        let eightMonthsAgo = calendar.date(byAdding: .month, value: -8, to: now)!
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!

        let oldSession = makeSession(date: eightMonthsAgo)
        let oldEntry = makeEntry(sessionId: oldSession.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            oldSession,
            entries: [oldEntry],
            sets: [oldEntry.id: [makeSet(exerciseEntryId: oldEntry.id, weight: 75.0, reps: 5)]]
        )

        let history = try test.memberPerformance.exerciseHistory(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: sixMonthsAgo
        )

        XCTAssertTrue(history.isEmpty)
    }

    func testTC_MP26_DeleteSessionWithNoPBsRemovesSessionAndEntries() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 100.0,
            reps: 5
        )
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 90.0, reps: 5)]]
        )

        try test.memberPerformance.deleteSession(id: session.id, memberId: testMemberId)

        let stored = try test.performanceDataAccess.fetchSession(id: session.id)
        XCTAssertNotNil(stored)
        XCTAssertNotNil(stored?.deletedAt)
        let entries = try test.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries.first?.deletedAt)
        let sets = try test.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
        XCTAssertEqual(sets.count, 1)
        XCTAssertNotNil(sets.first?.deletedAt)
    }

    func testTC_MP27_DeleteSessionContainingPBRemovesPBWhenNoHistory() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)]]
        )

        try test.memberPerformance.deleteSession(id: session.id, memberId: testMemberId)

        XCTAssertNotNil(try test.performanceDataAccess.fetchSession(id: session.id))
        XCTAssertNotNil(try test.performanceDataAccess.fetchSession(id: session.id)?.deletedAt)
        XCTAssertNil(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId))
        XCTAssertTrue(try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId).isEmpty)
    }

    func testTC_MP29_ResetCurrentPBCreatesExerciseResetAndClearsDerivedCurrent() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        try seedSetForDerivation(test: test, exerciseId: freeSquatId, weight: 85.0, reps: 5)

        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: freeSquatId)

        XCTAssertNotNil(try test.performanceDataAccess.fetchExerciseReset(memberId: testMemberId, exerciseId: freeSquatId))
        XCTAssertNil(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId))
    }

    func testTC_MP30_ResetCurrentPBHasNoEffectWhenNoCurrentPBExists() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        try test.memberPerformance.resetCurrentPB(memberId: testMemberId, exerciseId: freeSquatId)

        XCTAssertTrue(try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId).isEmpty)
        XCTAssertNil(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId))
    }

    func testTC_MP31_DeletePersonalBestRemovesTheRecord() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let pb = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 85.0,
            reps: 5
        )

        try test.memberPerformance.deletePersonalBest(
            id: pb.id,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        let remaining = try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotNil(remaining.first?.deletedAt)
    }

    func testTC_MP33_DeletePersonalBestLeavesNoCurrentPBWhenDeletingOnlyRecord() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let pb = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 85.0,
            reps: 5
        )

        try test.memberPerformance.deletePersonalBest(
            id: pb.id,
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        XCTAssertNil(try derivedCurrentPB(memberPerformance: test.memberPerformance, exerciseId: freeSquatId))
        let remaining = try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotNil(remaining.first?.deletedAt)
    }
}
#endif
