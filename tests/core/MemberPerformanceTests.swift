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
            performanceDataAccess: performanceDataAccess
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
        isCurrent: Bool = true,
        entryType: PBEntryType = .sessionDerived
    ) throws -> PersonalBestModel {
        let pb = PersonalBestModel(
            memberId: testMemberId,
            exerciseId: exerciseId,
            setId: UUID(),
            weight: weight,
            reps: reps,
            time: time,
            distance: distance,
            achievedAt: achievedAt,
            isCurrent: isCurrent,
            entryType: entryType
        )
        try performanceDataAccess.savePersonalBest(pb)
        return pb
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
        #expect(result.newPBs.first?.isCurrent == true)
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
        let currentPB = try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(currentPB?.weight == 100.0)
        #expect(currentPB?.isCurrent == true)
    }

    @Test
    func testTC_MP3_SaveASessionThatBeatsAnExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")

        let oldPB = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5
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
        #expect(result.newPBs.first?.isCurrent == true)

        let allPBs = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )
        #expect(allPBs.count == 2)
        #expect(allPBs.first(where: { $0.id == oldPB.id })?.isCurrent == false)
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
        #expect(result.newPBs.allSatisfy { $0.isCurrent == true })
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
    func testTC_MP6_RejectASessionWithNoExerciseEntries() throws {
        let test = try makeMemberPerformance()
        let session = makeSession()

        #expect(throws: MemberPerformanceError.emptySession) {
            _ = try test.memberPerformance.saveSession(session, entries: [], sets: [:])
        }

        let storedSessions = try test.context.fetch(FetchDescriptor<SessionModel>())
        #expect(storedSessions.isEmpty)
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

        let pbBeforeUpdate = try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        session.notes = "Updated notes"
        session.updatedAt = Date().addingTimeInterval(1)
        try test.memberPerformance.updateSession(session)

        let fetchedSession = try test.performanceDataAccess.fetchSession(id: session.id)
        let pbAfterUpdate = try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
            exerciseId: freeSquatId
        )

        #expect(fetchedSession?.notes == "Updated notes")
        #expect(pbAfterUpdate?.id == pbBeforeUpdate?.id)
        #expect(pbAfterUpdate?.weight == pbBeforeUpdate?.weight)
        #expect(pbAfterUpdate?.reps == pbBeforeUpdate?.reps)
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
            distance: nil
        )

        #expect(result.isNewPB == true)
        #expect(result.personalBest != nil)
        #expect(result.personalBest?.entryType == .manualEntry)
        #expect(result.personalBest?.setId == nil)
        #expect(result.personalBest?.isCurrent == true)
        #expect(
            Calendar.current.isDate(result.personalBest!.achievedAt, inSameDayAs: Date()),
            "Expected achievedAt to be today's date"
        )
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
            distance: nil
        )

        #expect(result.isNewPB == true)
        #expect(result.personalBest?.isCurrent == true)

        let superseded = try test.performanceDataAccess.fetchAllPBs(
            memberId: testMemberId,
            exerciseId: freeSquatId
        ).first(where: { $0.id == oldPB.id })
        #expect(superseded?.isCurrent == false)
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
            distance: nil
        )

        #expect(result.isNewPB == false)
        #expect(result.personalBest == nil)

        let currentPB = try test.performanceDataAccess.fetchCurrentPB(
            memberId: testMemberId,
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
                distance: nil
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
            distance: nil
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

        #expect(allPBs.count == 2)
        #expect(allPBs.contains(where: { $0.entryType == .manualEntry }))
        #expect(allPBs.contains(where: { $0.entryType == .sessionDerived && $0.isCurrent == true }))
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

        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5
        )
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
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

        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 70.0,
            reps: 5,
            isCurrent: false
        )
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5,
            isCurrent: true
        )

        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)

        #expect(currentPBs.count == 1)
        #expect(currentPBs.first?.weight == 80.0)
        #expect(currentPBs.first?.isCurrent == true)
    }

    @Test
    func testTC_MP16_CurrentPBsReturnsResultsOrderedByExerciseDisplayOrder() throws {
        let test = try makeMemberPerformance()
        let overheadPressId = seedExerciseId(named: "Overhead Press")
        let freeSquatId = seedExerciseId(named: "Free Squat")

        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5
        )
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: overheadPressId,
            weight: 50.0,
            reps: 5
        )

        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)

        #expect(currentPBs.count == 2)
        #expect(currentPBs[0].exerciseId == overheadPressId)
        #expect(currentPBs[1].exerciseId == freeSquatId)
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
            achievedAt: eightMonthsAgo,
            isCurrent: false
        )
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 75.0,
            reps: 5,
            achievedAt: fiveMonthsAgo,
            isCurrent: false
        )
        _ = try saveExistingPB(
            performanceDataAccess: test.performanceDataAccess,
            exerciseId: freeSquatId,
            weight: 80.0,
            reps: 5,
            achievedAt: oneMonthAgo,
            isCurrent: true
        )

        let progression = try test.memberPerformance.pbProgression(
            memberId: testMemberId,
            exerciseId: freeSquatId,
            from: sixMonthsAgo
        )

        #expect(progression.count == 2)
        #expect(progression.map(\.weight) == [75.0, 80.0])
        #expect(progression.map(\.achievedAt) == progression.map(\.achievedAt).sorted())
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
            performanceDataAccess: performanceDataAccess
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
        isCurrent: Bool = true,
        entryType: PBEntryType = .sessionDerived
    ) throws -> PersonalBestModel {
        let pb = PersonalBestModel(
            memberId: testMemberId,
            exerciseId: exerciseId,
            setId: UUID(),
            weight: weight,
            reps: reps,
            time: time,
            distance: distance,
            achievedAt: achievedAt,
            isCurrent: isCurrent,
            entryType: entryType
        )
        try performanceDataAccess.savePersonalBest(pb)
        return pb
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
        XCTAssertTrue(result.newPBs.first?.isCurrent == true)
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
    }

    func testTC_MP3_SaveASessionThatBeatsAnExistingPB() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        let oldPB = try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5)

        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        let result = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)]]
        )

        XCTAssertEqual(result.newPBs.count, 1)
        let allPBs = try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId)
        XCTAssertEqual(allPBs.count, 2)
        XCTAssertFalse(allPBs.first(where: { $0.id == oldPB.id })?.isCurrent ?? true)
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

    func testTC_MP6_RejectASessionWithNoExerciseEntries() throws {
        let test = try makeMemberPerformance()
        XCTAssertThrowsError(try test.memberPerformance.saveSession(makeSession(), entries: [], sets: [:]))
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
        let pbBefore = try test.performanceDataAccess.fetchCurrentPB(memberId: testMemberId, exerciseId: freeSquatId)
        session.notes = "Updated notes"
        try test.memberPerformance.updateSession(session)
        let pbAfter = try test.performanceDataAccess.fetchCurrentPB(memberId: testMemberId, exerciseId: freeSquatId)
        XCTAssertEqual(pbAfter?.id, pbBefore?.id)
    }

    func testTC_MP9_RecordAManualPBWithNoExistingPB() throws {
        let test = try makeMemberPerformance()
        let result = try test.memberPerformance.recordManualPB(
            exerciseId: seedExerciseId(named: "Free Squat"),
            memberId: testMemberId,
            weight: 80.0,
            reps: 5,
            time: nil,
            distance: nil
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
            distance: nil
        )
        XCTAssertTrue(result.isNewPB)
        let superseded = try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId)
            .first(where: { $0.id == oldPB.id })
        XCTAssertFalse(superseded?.isCurrent ?? true)
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
            distance: nil
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
                distance: nil
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
            distance: nil
        )
        let session = makeSession()
        let entry = makeEntry(sessionId: session.id, exerciseId: freeSquatId)
        _ = try test.memberPerformance.saveSession(
            session,
            entries: [entry],
            sets: [entry.id: [makeSet(exerciseEntryId: entry.id, weight: 85.0, reps: 5)]]
        )
        let allPBs = try test.performanceDataAccess.fetchAllPBs(memberId: testMemberId, exerciseId: freeSquatId)
        XCTAssertEqual(allPBs.count, 2)
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
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5)
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: conditioningExercise.id, time: 90.0)
        let currentPBs = try test.memberPerformance.currentPBs(memberId: testMemberId)
        XCTAssertEqual(currentPBs.count, 1)
    }

    func testTC_MP15_CurrentPBsReturnsOneRecordPerExercise() throws {
        let test = try makeMemberPerformance()
        let freeSquatId = seedExerciseId(named: "Free Squat")
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 70.0, reps: 5, isCurrent: false)
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5, isCurrent: true)
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
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 70.0, reps: 5, achievedAt: calendar.date(byAdding: .month, value: -8, to: now)!, isCurrent: false)
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 75.0, reps: 5, achievedAt: calendar.date(byAdding: .month, value: -5, to: now)!, isCurrent: false)
        try saveExistingPB(performanceDataAccess: test.performanceDataAccess, exerciseId: freeSquatId, weight: 80.0, reps: 5, achievedAt: calendar.date(byAdding: .month, value: -1, to: now)!, isCurrent: true)
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
}
#endif
