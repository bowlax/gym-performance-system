import Foundation

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

    init(exerciseRegistry: ExerciseRegistry, performanceDataAccess: PerformanceDataAccess) {
        self.exerciseRegistry = exerciseRegistry
        self.performanceDataAccess = performanceDataAccess
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

            for set in sets[entry.id] ?? [] {
                let currentPB = try performanceDataAccess.fetchCurrentPB(
                    memberId: session.memberId,
                    exerciseId: entry.exerciseId
                )

                guard exerciseRegistry.isPB(set: set, exercise: exercise, currentPB: currentPB) else {
                    continue
                }

                if let currentPB {
                    try performanceDataAccess.markPBAsSuperseded(id: currentPB.id)
                }

                let personalBest = PersonalBestModel(
                    memberId: session.memberId,
                    exerciseId: entry.exerciseId,
                    setId: set.id,
                    weight: set.weight,
                    reps: set.reps,
                    time: set.time,
                    distance: set.distance,
                    achievedAt: session.date,
                    isCurrent: true,
                    entryType: .sessionDerived
                )

                try performanceDataAccess.savePersonalBest(personalBest)
                newPBs.append(personalBest)
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
        achievedAt: Date
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

        let currentPB = try performanceDataAccess.fetchCurrentPB(
            memberId: memberId,
            exerciseId: exerciseId
        )

        guard exerciseRegistry.isPB(set: evaluationSet, exercise: exercise, currentPB: currentPB) else {
            return ManualPBResult(isNewPB: false, personalBest: nil)
        }

        if let currentPB {
            try performanceDataAccess.markPBAsSuperseded(id: currentPB.id)
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
            isCurrent: true,
            entryType: .manualEntry
        )

        try performanceDataAccess.savePersonalBest(personalBest)

        return ManualPBResult(isNewPB: true, personalBest: personalBest)
    }

    func currentPBs(memberId: UUID) throws -> [PersonalBestModel] {
        let pbExercises = try exerciseRegistry.pbExercises()
        let displayOrderByExerciseId = Dictionary(
            uniqueKeysWithValues: pbExercises.map { ($0.id, $0.displayOrder) }
        )
        let pbExerciseIds = Set(pbExercises.map(\.id))

        let currentPBs = try performanceDataAccess.fetchCurrentPBs(memberId: memberId)

        return currentPBs
            .filter { pbExerciseIds.contains($0.exerciseId) }
            .sorted {
                (displayOrderByExerciseId[$0.exerciseId] ?? Int.max)
                    < (displayOrderByExerciseId[$1.exerciseId] ?? Int.max)
            }
    }

    func pbProgression(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [PersonalBestModel] {
        let allPBs = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        return allPBs
            .filter { $0.achievedAt >= from }
            .sorted { $0.achievedAt < $1.achievedAt }
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

        let personalBests = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        let pbSetIds = Set(personalBests.compactMap(\.setId))

        let sessions = try performanceDataAccess.fetchSessions(memberId: memberId)
            .filter { $0.date >= from }
            .sorted { $0.date < $1.date }

        var history: [ExerciseSetSummary] = []

        for session in sessions {
            let entries = try performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
                .filter { $0.exerciseId == exerciseId }

            guard !entries.isEmpty else { continue }

            var sets: [ModelSet] = []
            for entry in entries {
                sets.append(contentsOf: try performanceDataAccess.fetchSets(exerciseEntryId: entry.id))
            }

            guard let bestSet = bestSet(from: sets, exercise: exercise) else { continue }

            let isPB = pbSetIds.contains(bestSet.id)
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
                try handlePersonalBestForDeletedSet(
                    set: set,
                    memberId: memberId,
                    exerciseId: entry.exerciseId,
                    store: store
                )
                try store.removeSet(set)
            }

            try store.removeExerciseEntry(entry)
        }

        try store.removeSession(session)
    }

    func resetCurrentPB(memberId: UUID, exerciseId: UUID) throws {
        guard let currentPB = try performanceDataAccess.fetchCurrentPB(
            memberId: memberId,
            exerciseId: exerciseId
        ) else {
            return
        }

        guard let store = performanceDataAccess as? SwiftDataPerformanceDataAccess else {
            return
        }

        try store.markPBAsReset(id: currentPB.id)
    }

    func deletePersonalBest(id: UUID, memberId: UUID, exerciseId: UUID) throws {
        guard let store = performanceDataAccess as? SwiftDataPerformanceDataAccess else {
            return
        }

        let allPBs = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        guard let pb = allPBs.first(where: { $0.id == id }) else { return }
        guard pb.memberId == memberId else { return }

        let wasCurrent = pb.isCurrent
        try store.removePersonalBest(pb)

        if wasCurrent {
            try promoteBestRestorablePersonalBest(
                memberId: memberId,
                exerciseId: exerciseId,
                store: store
            )
        }
    }

    func projectedCurrentPBAfterDeletingHistoryEntry(
        setId: UUID?,
        personalBestId: UUID?,
        memberId: UUID,
        exerciseId: UUID
    ) throws -> PersonalBestModel? {
        guard let exercise = try exerciseRegistry.exercise(id: exerciseId) else { return nil }
        let allPBs = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        let currentPB = allPBs.first(where: \.isCurrent)

        guard deletionRemovesCurrentPB(
            setId: setId,
            personalBestId: personalBestId,
            currentPB: currentPB,
            allPBs: allPBs
        ) else {
            return currentPB
        }

        var excludingIds = Set<UUID>()
        var excludingSetIds = Set<UUID>()

        if let personalBestId {
            excludingIds.insert(personalBestId)
        }
        if let setId {
            excludingSetIds.insert(setId)
            if let linkedPB = allPBs.first(where: { $0.setId == setId }) {
                excludingIds.insert(linkedPB.id)
            }
        }

        return PersonalBestRanking.bestRestorable(
            from: allPBs,
            exercise: exercise,
            excludingIds: excludingIds,
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
                try handlePersonalBestForDeletedSet(
                    set: set,
                    memberId: memberId,
                    exerciseId: exerciseId,
                    store: store
                )
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

    private func handlePersonalBestForDeletedSet(
        set: ModelSet,
        memberId: UUID,
        exerciseId: UUID,
        store: SwiftDataPerformanceDataAccess
    ) throws {
        let allPBs = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
        let matchingPBs = allPBs.filter { $0.setId == set.id }
        guard let pb = matchingPBs.first(where: \.isCurrent)
            ?? matchingPBs.max(by: { $0.achievedAt < $1.achievedAt }) else {
            return
        }

        let wasCurrent = pb.isCurrent
        try store.removePersonalBest(pb)

        if wasCurrent {
            try promoteBestRestorablePersonalBest(
                memberId: memberId,
                exerciseId: exerciseId,
                store: store
            )
        }
    }

    private func promoteBestRestorablePersonalBest(
        memberId: UUID,
        exerciseId: UUID,
        store: SwiftDataPerformanceDataAccess
    ) throws {
        guard let exercise = try exerciseRegistry.exercise(id: exerciseId) else { return }
        let remaining = try performanceDataAccess.fetchAllPBs(
            memberId: memberId,
            exerciseId: exerciseId
        )
        guard let previous = PersonalBestRanking.bestRestorable(from: remaining, exercise: exercise) else {
            return
        }
        try store.setPersonalBestCurrent(id: previous.id, isCurrent: true)
    }

    private func deletionRemovesCurrentPB(
        setId: UUID?,
        personalBestId: UUID?,
        currentPB: PersonalBestModel?,
        allPBs: [PersonalBestModel]
    ) -> Bool {
        guard let currentPB else { return false }
        if personalBestId == currentPB.id { return true }
        if let setId, currentPB.setId == setId { return true }
        if let setId,
           let linkedPB = allPBs.first(where: { $0.setId == setId }),
           linkedPB.id == currentPB.id {
            return true
        }
        return false
    }

    private func bestSet(from sets: [ModelSet], exercise: ExerciseModel) -> ModelSet? {
        guard let pbRule = exercise.pbRule else { return nil }

        switch pbRule {
        case .heaviestWeightAtReps, .bestWeightAndReps:
            return sets
                .filter { $0.weight != nil && $0.reps != nil }
                .max {
                    let leftWeight = $0.weight ?? 0
                    let rightWeight = $1.weight ?? 0

                    if leftWeight != rightWeight {
                        return leftWeight < rightWeight
                    }

                    return ($0.reps ?? 0) < ($1.reps ?? 0)
                }

        case .heaviestWeight:
            return sets
                .filter { $0.weight != nil }
                .max { ($0.weight ?? 0) < ($1.weight ?? 0) }

        case .fastestTime:
            return sets
                .filter { $0.time != nil }
                .min { ($0.time ?? .infinity) < ($1.time ?? .infinity) }

        case .longestDistance:
            return sets
                .filter { $0.distance != nil }
                .max { ($0.distance ?? 0) < ($1.distance ?? 0) }

        case .mostReps:
            return sets
                .filter { $0.reps != nil }
                .max { ($0.reps ?? 0) < ($1.reps ?? 0) }
        }
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
