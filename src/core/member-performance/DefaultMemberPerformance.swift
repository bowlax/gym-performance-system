import Foundation
import SwiftData

enum MemberPerformanceError: Error, Equatable {
    case emptySession
    case exerciseEntryMissingSets(UUID)
    case invalidExercise(UUID)
    case inactiveExercise(UUID)
    case invalidMeasurementFields(MeasurementType)
    case sessionNotFound(UUID)
    case setNotFound(UUID)
}

final class DefaultMemberPerformance: MemberPerformance {
    private let exerciseRegistry: ExerciseRegistry
    private let performanceDataAccess: PerformanceDataAccess
    private let modelContext: ModelContext

    init(
        exerciseRegistry: ExerciseRegistry,
        performanceDataAccess: PerformanceDataAccess,
        modelContext: ModelContext
    ) {
        self.exerciseRegistry = exerciseRegistry
        self.performanceDataAccess = performanceDataAccess
        self.modelContext = modelContext
    }

    func saveSession(
        _ session: SessionModel,
        entries: [ExerciseEntryModel],
        sets: [UUID: [ModelSet]]
    ) throws -> SessionResult {
        if entries.isEmpty {
            try performanceDataAccess.saveSession(session)
            return SessionResult(session: session, newPBs: [])
        }

        var exercisesByEntryId: [UUID: ExerciseModel] = [:]

        for entry in entries {
            guard let exerciseSets = sets[entry.id], !exerciseSets.isEmpty else {
                throw MemberPerformanceError.exerciseEntryMissingSets(entry.id)
            }

            guard let exercise = try exerciseRegistry.exercise(id: entry.exerciseId) else {
                throw MemberPerformanceError.invalidExercise(entry.exerciseId)
            }

            guard exercise.isActive else {
                throw MemberPerformanceError.inactiveExercise(entry.exerciseId)
            }

            exercisesByEntryId[entry.id] = exercise

            for set in exerciseSets {
                try validateMeasurementFields(
                    measurementType: exercise.measurementType,
                    weight: set.weight,
                    reps: set.reps,
                    time: set.time,
                    distance: set.distance
                )
            }
        }

        var beforeByExercise: [UUID: PBReadDerivation.ExerciseResult] = [:]
        for entry in entries {
            guard let exercise = exercisesByEntryId[entry.id] else { continue }
            beforeByExercise[entry.exerciseId] = try PBReadDerivation.derive(
                memberId: session.memberId,
                exercise: exercise,
                performanceDataAccess: performanceDataAccess,
                modelContext: modelContext
            )
        }

        try performanceDataAccess.saveSession(session)

        for entry in entries {
            try performanceDataAccess.saveExerciseEntry(entry)
            for set in sets[entry.id] ?? [] {
                try performanceDataAccess.saveSet(set)
            }
        }

        var newPBs: [PersonalBestModel] = []

        for entry in entries {
            guard let exercise = exercisesByEntryId[entry.id] else { continue }
            let before = beforeByExercise[entry.exerciseId]

            let after = try PBReadDerivation.derive(
                memberId: session.memberId,
                exercise: exercise,
                performanceDataAccess: performanceDataAccess,
                modelContext: modelContext
            )

            var sessionSetIds = Set<UUID>()
            var sessionSets: [ModelSet] = []
            for set in sets[entry.id] ?? [] {
                sessionSetIds.insert(set.id)
                sessionSets.append(set)
            }

            if let celebrated = SessionPBCelebration.earnedNewPB(
                exercise: exercise,
                before: before,
                after: after,
                sessionSetIds: sessionSetIds,
                sessionSets: sessionSets
            ) {
                newPBs.append(celebrated)
            }
        }

        return SessionResult(session: session, newPBs: newPBs)
    }

    func updateSession(_ session: SessionModel) throws {
        try performanceDataAccess.updateSession(session)
    }

    func updateSet(_ set: ModelSet) throws {
        try performanceDataAccess.updateSet(set)
    }

    func recordManualPB(
        exerciseId: UUID,
        memberId: UUID,
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?,
        achievedAt: Date?
    ) throws -> ManualPBResult {
        guard let exercise = try exerciseRegistry.exercise(id: exerciseId) else {
            throw MemberPerformanceError.invalidExercise(exerciseId)
        }

        guard exercise.isActive else {
            throw MemberPerformanceError.inactiveExercise(exerciseId)
        }

        try validateMeasurementFields(
            measurementType: exercise.measurementType,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )

        let evaluationSet = ModelSet(
            exerciseEntryId: UUID(),
            weight: weight,
            reps: reps,
            time: time,
            distance: distance
        )

        let derived = try PBReadDerivation.derive(
            memberId: memberId,
            exercise: exercise,
            performanceDataAccess: performanceDataAccess,
            modelContext: modelContext
        )

        guard exerciseRegistry.isPB(
            set: evaluationSet,
            exercise: exercise,
            currentPB: derived.currentPB
        ) else {
            return ManualPBResult(isNewPB: false, personalBest: nil)
        }

        let personalBest = PersonalBestModel(
            memberId: memberId,
            exerciseId: exerciseId,
            setId: nil,
            weight: weight,
            reps: reps,
            time: time,
            distance: distance,
            achievedAt: achievedAt,
            entryType: .manualEntry
        )

        try performanceDataAccess.savePersonalBest(personalBest)

        return ManualPBResult(isNewPB: true, personalBest: personalBest)
    }

    func updateManualPB(
        id: UUID,
        memberId: UUID,
        exerciseId: UUID,
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?,
        achievedAt: Date?
    ) throws {
        guard let store = performanceDataAccess as? SwiftDataPerformanceDataAccess else {
            return
        }

        let allPBs = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        guard let pb = allPBs.first(where: {
            $0.id == id
                && $0.memberId == memberId
                && $0.entryType == .manualEntry
                && $0.deletedAt == nil
        }) else {
            return
        }

        pb.weight = weight
        pb.reps = reps
        pb.time = time
        pb.distance = distance
        pb.achievedAt = achievedAt
        pb.updatedAt = Date()
        try store.persistChanges()
    }

    func currentPBs(memberId: UUID) throws -> [PersonalBestModel] {
        let pbExercises = try exerciseRegistry.pbExercises()
            .sorted { $0.displayOrder < $1.displayOrder }
        return try PBReadDerivation.deriveAllCurrentPBs(
            memberId: memberId,
            exercises: pbExercises,
            performanceDataAccess: performanceDataAccess,
            modelContext: modelContext
        )
    }

    func deriveExerciseReadState(
        memberId: UUID,
        exerciseId: UUID
    ) throws -> PBReadDerivation.ExerciseResult {
        guard let exercise = try exerciseRegistry.exercise(id: exerciseId) else {
            throw MemberPerformanceError.invalidExercise(exerciseId)
        }
        return try PBReadDerivation.derive(
            memberId: memberId,
            exercise: exercise,
            performanceDataAccess: performanceDataAccess,
            modelContext: modelContext
        )
    }

    func pbProgression(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [PersonalBestModel] {
        let allPBs = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        return allPBs
            .filter { pb in
                guard pb.entryType == .manualEntry, let achievedAt = pb.achievedAt else { return false }
                return achievedAt >= from
            }
            .sorted { ($0.achievedAt ?? .distantPast) < ($1.achievedAt ?? .distantPast) }
    }

    func sessionConsistency(
        memberId: UUID,
        from: Date
    ) throws -> [WeeklySessionCount] {
        let calendar = mondayCalendar()
        let sessions = try performanceDataAccess.fetchSessions(memberId: memberId)
            .filter { $0.date >= from }

        var weekStart = startOfWeek(for: from, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        var weeklyCounts: [WeeklySessionCount] = []

        while weekStart <= today {
            guard let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                break
            }

            let count = sessions.filter { session in
                session.date >= weekStart && session.date < nextWeekStart
            }.count

            weeklyCounts.append(WeeklySessionCount(weekStarting: weekStart, count: count))
            weekStart = nextWeekStart
        }

        return weeklyCounts
    }

    func exerciseHistory(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [ExerciseSetSummary] {
        guard let exercise = try exerciseRegistry.exercise(id: exerciseId) else {
            throw MemberPerformanceError.invalidExercise(exerciseId)
        }

        let derived = try deriveExerciseReadState(memberId: memberId, exerciseId: exerciseId)
        let badgeIds = derived.badgeIds

        let sessions = try performanceDataAccess.fetchSessions(memberId: memberId)
            .filter { $0.deletedAt == nil && $0.date >= from }
            .sorted { $0.date < $1.date }

        var history: [ExerciseSetSummary] = []

        for session in sessions {
            let entries = try performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
                .filter { $0.exerciseId == exerciseId && $0.deletedAt == nil }

            guard !entries.isEmpty else { continue }

            var sets: [ModelSet] = []
            for entry in entries {
                sets.append(
                    contentsOf: try performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                        .filter { $0.deletedAt == nil }
                )
            }

            guard let bestSet = bestSet(from: sets, exercise: exercise) else { continue }

            let isPB = badgeIds.contains(bestSet.id.uuidString)
            history.append(
                ExerciseSetSummary(
                    sessionDate: session.date,
                    set: bestSet,
                    isPB: isPB
                )
            )
        }

        return history
    }

    func deleteSession(id: UUID, memberId: UUID) throws {
        guard let session = try performanceDataAccess.fetchSession(id: id) else {
            throw MemberPerformanceError.sessionNotFound(id)
        }

        guard session.memberId == memberId else {
            throw MemberPerformanceError.sessionNotFound(id)
        }

        guard let store = performanceDataAccess as? SwiftDataPerformanceDataAccess else {
            throw MemberPerformanceError.sessionNotFound(id)
        }

        let entries = try performanceDataAccess.fetchExerciseEntries(sessionId: id)

        for entry in entries {
            let sets = try performanceDataAccess.fetchSets(exerciseEntryId: entry.id)

            for set in sets {
                try store.removeSet(set)
            }

            try store.removeExerciseEntry(entry)
        }

        try store.removeSession(session)
    }

    func resetCurrentPB(memberId: UUID, exerciseId: UUID, undo: Bool = false) throws {
        guard let store = performanceDataAccess as? SwiftDataPerformanceDataAccess else {
            return
        }

        if undo {
            try store.undoExerciseReset(memberId: memberId, exerciseId: exerciseId)
            return
        }

        let todayISO = PBDerivation.formatISODate(Date())
        let resetDay = PBDerivation.parseISODate(todayISO)
        _ = try store.upsertExerciseReset(
            memberId: memberId,
            exerciseId: exerciseId,
            resetAt: resetDay
        )
    }

    func deletePersonalBest(id: UUID, memberId: UUID, exerciseId: UUID) throws {
        guard let store = performanceDataAccess as? SwiftDataPerformanceDataAccess else {
            return
        }

        let allPBs = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        guard let pb = allPBs.first(where: { $0.id == id && $0.entryType == .manualEntry }) else { return }
        guard pb.memberId == memberId else { return }

        try store.removePersonalBest(pb)
    }

    func projectedCurrentPBAfterDeletingHistoryEntry(
        setId: UUID?,
        personalBestId: UUID?,
        memberId: UUID,
        exerciseId: UUID
    ) throws -> PersonalBestModel? {
        guard let exercise = try exerciseRegistry.exercise(id: exerciseId) else { return nil }

        let derived = try deriveExerciseReadState(memberId: memberId, exerciseId: exerciseId)
        guard deletionRemovesCurrentPB(
            setId: setId,
            personalBestId: personalBestId,
            currentPB: derived.currentPB
        ) else {
            return derived.currentPB
        }

        var excludingIds = Set<String>()
        var excludingSetIds = Set<UUID>()

        if let personalBestId {
            excludingIds.insert(personalBestId.uuidString)
        }
        if let setId {
            excludingSetIds.insert(setId)
        }

        return try PBReadDerivation.deriveCurrentPBExcluding(
            memberId: memberId,
            exercise: exercise,
            performanceDataAccess: performanceDataAccess,
            modelContext: modelContext,
            excludingRecordIds: excludingIds,
            excludingSetIds: excludingSetIds
        )
    }

    func deleteHistoryEntry(
        setId: UUID?,
        personalBestId: UUID?,
        memberId: UUID,
        exerciseId: UUID
    ) throws {
        guard let store = performanceDataAccess as? SwiftDataPerformanceDataAccess else {
            return
        }

        if let setId {
            if let set = try resolveSet(
                id: setId,
                memberId: memberId,
                exerciseId: exerciseId
            ) {
                try store.removeSet(set)
                return
            }

            if personalBestId == nil {
                throw MemberPerformanceError.setNotFound(setId)
            }
        }

        if let personalBestId {
            try deletePersonalBest(
                id: personalBestId,
                memberId: memberId,
                exerciseId: exerciseId
            )
        }
    }

    private func resolveSet(
        id: UUID,
        memberId: UUID,
        exerciseId: UUID
    ) throws -> ModelSet? {
        let sessions = try performanceDataAccess.fetchSessions(memberId: memberId)

        for session in sessions {
            let entries = try performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
                .filter { $0.exerciseId == exerciseId }

            for entry in entries {
                if let set = try performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                    .first(where: { $0.id == id }) {
                    return set
                }
            }
        }

        return nil
    }

    private func deletionRemovesCurrentPB(
        setId: UUID?,
        personalBestId: UUID?,
        currentPB: PersonalBestModel?
    ) -> Bool {
        guard let currentPB else { return false }
        if personalBestId == currentPB.id { return true }
        if let setId, currentPB.setId == setId { return true }
        return false
    }

    private func bestSet(from sets: [ModelSet], exercise: ExerciseModel) -> ModelSet? {
        guard let pbRule = exercise.pbRule else { return nil }
        return PBRuleEvaluator.bestSet(among: sets, rule: pbRule)
    }

    private func validateMeasurementFields(
        measurementType: MeasurementType,
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?
    ) throws {
        let isValid: Bool

        switch measurementType {
        case .weightAndReps:
            isValid = weight != nil && reps != nil
        case .weightAndTime:
            isValid = weight != nil && time != nil
        case .timeOnly:
            isValid = time != nil
        case .distanceOnly:
            isValid = distance != nil
        case .repsOnly:
            isValid = reps != nil
        case .weightAndDistance:
            isValid = weight != nil && distance != nil
        }

        guard isValid else {
            throw MemberPerformanceError.invalidMeasurementFields(measurementType)
        }
    }

    private func mondayCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
