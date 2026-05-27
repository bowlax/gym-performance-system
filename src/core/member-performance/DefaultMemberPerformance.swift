import Foundation

enum MemberPerformanceError: Error, Equatable {
    case emptySession
    case exerciseEntryMissingSets(UUID)
    case invalidExercise(UUID)
    case inactiveExercise(UUID)
    case invalidMeasurementFields(MeasurementType)
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
        guard !entries.isEmpty else {
            throw MemberPerformanceError.emptySession
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
        distance: Double?
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
            achievedAt: Date(),
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
