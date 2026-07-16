import Foundation
import SwiftData

/// Builds derivation inputs from local store and runs `PBDerivation` for reads (#28 step 3).
enum PBReadDerivation {
    /// Wall-clock duration of the last `deriveAllCurrentPBs` call (board load instrumentation).
    private(set) static var lastBoardDerivationSeconds: TimeInterval?

    struct ExerciseResult: Equatable {
        var currentPB: PersonalBestModel?
        var lifetimePB: PersonalBestModel?
        var badgeIds: Set<String>
        var resetAt: Date?
        var stalenessEnabled: Bool
    }

    static func todayISO() -> String {
        PBDerivation.formatISODate(Calendar(identifier: .gregorian).startOfDay(for: Date()))
    }

    static func staleness(
        from setting: MemberStalenessSetting
    ) -> PBDerivation.StalenessSetting {
        PBDerivation.StalenessSetting(
            enabled: setting.enabled,
            periods: setting.periods,
            unit: setting.unit == .month ? .months : .quarters
        )
    }

    static func personalBest(
        from record: PBDerivation.Record,
        memberId: UUID,
        exerciseId: UUID
    ) -> PersonalBestModel {
        let id = UUID(uuidString: record.id) ?? UUID()
        let achievedAt = record.achievedAt.map(PBDerivation.parseISODate)
        let entryType: PBEntryType = record.entryKind == "manual" || record.entryKind == "manualEntry"
            ? .manualEntry
            : .sessionDerived
        return PersonalBestModel(
            id: id,
            memberId: memberId,
            exerciseId: exerciseId,
            setId: entryType == .sessionDerived ? id : nil,
            weight: record.weight,
            reps: record.reps,
            time: record.time,
            distance: record.distance,
            achievedAt: achievedAt,
            entryType: entryType
        )
    }

    /// All sets for the exercise + manual PB entries as derivation records.
    static func records(
        memberId: UUID,
        exerciseId: UUID,
        performanceDataAccess: PerformanceDataAccess
    ) throws -> [PBDerivation.Record] {
        var records: [PBDerivation.Record] = []

        let sessions = try performanceDataAccess.fetchSessions(memberId: memberId)
        for session in sessions where session.deletedAt == nil {
            let entries = try performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
                .filter { $0.exerciseId == exerciseId && $0.deletedAt == nil }
            for entry in entries {
                let sets = try performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                    .filter { $0.deletedAt == nil }
                for set in sets {
                    records.append(
                        PBDerivation.Record(
                            id: set.id.uuidString,
                            achievedAt: PBDerivation.formatISODate(session.date),
                            weight: set.weight,
                            reps: set.reps,
                            time: set.time,
                            distance: set.distance,
                            entryKind: "set"
                        )
                    )
                }
            }
        }

        let manuals = try performanceDataAccess.fetchAllPBs(memberId: memberId, exerciseId: exerciseId)
            .filter { $0.entryType == .manualEntry && $0.deletedAt == nil }
        for pb in manuals {
            records.append(
                PBDerivation.Record(
                    id: pb.id.uuidString,
                    achievedAt: pb.achievedAt.map(PBDerivation.formatISODate),
                    weight: pb.weight,
                    reps: pb.reps,
                    time: pb.time,
                    distance: pb.distance,
                    entryKind: "manual"
                )
            )
        }

        return records
    }

    static func resetAtISO(
        memberId: UUID,
        exerciseId: UUID,
        in context: ModelContext
    ) throws -> String? {
        let descriptor = FetchDescriptor<ExerciseResetModel>(
            predicate: #Predicate {
                $0.memberId == memberId && $0.exerciseId == exerciseId
            }
        )
        guard let row = try context.fetch(descriptor).first,
              row.deletedAt == nil else {
            return nil
        }
        return PBDerivation.formatISODate(row.resetAt)
    }

    static func resetAtDate(
        memberId: UUID,
        exerciseId: UUID,
        in context: ModelContext
    ) throws -> Date? {
        guard let iso = try resetAtISO(memberId: memberId, exerciseId: exerciseId, in: context) else {
            return nil
        }
        return PBDerivation.parseISODate(iso)
    }

    static func derive(
        memberId: UUID,
        exercise: ExerciseModel,
        performanceDataAccess: PerformanceDataAccess,
        modelContext: ModelContext,
        evaluatedAt: String = todayISO()
    ) throws -> ExerciseResult {
        guard let rule = exercise.pbRule else {
            return ExerciseResult(
                currentPB: nil,
                lifetimePB: nil,
                badgeIds: [],
                resetAt: nil,
                stalenessEnabled: false
            )
        }

        let memberSetting = try MemberState.stalenessSetting(in: modelContext, memberId: memberId)
        let staleness = staleness(from: memberSetting)
        let records = try records(
            memberId: memberId,
            exerciseId: exercise.id,
            performanceDataAccess: performanceDataAccess
        )
        let resetISO = try resetAtISO(
            memberId: memberId,
            exerciseId: exercise.id,
            in: modelContext
        )
        let derived = PBDerivation.derivePBs(
            rule: rule,
            records: records,
            staleness: staleness,
            resetAt: resetISO,
            evaluatedAt: evaluatedAt
        )
        let badges = Set(
            PBDerivation.badgeIds(rule: rule, records: records)
        )

        return ExerciseResult(
            currentPB: derived.currentPB.map {
                personalBest(from: $0, memberId: memberId, exerciseId: exercise.id)
            },
            lifetimePB: derived.lifetimePB.map {
                personalBest(from: $0, memberId: memberId, exerciseId: exercise.id)
            },
            badgeIds: badges,
            resetAt: resetISO.map(PBDerivation.parseISODate),
            stalenessEnabled: memberSetting.enabled
        )
    }

    /// Derives current PB for every PB exercise (board). Times wall clock into `lastBoardDerivationSeconds`.
    static func deriveAllCurrentPBs(
        memberId: UUID,
        exercises: [ExerciseModel],
        performanceDataAccess: PerformanceDataAccess,
        modelContext: ModelContext
    ) throws -> [PersonalBestModel] {
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            lastBoardDerivationSeconds = CFAbsoluteTimeGetCurrent() - started
        }

        let memberSetting = try MemberState.stalenessSetting(in: modelContext, memberId: memberId)
        let staleness = staleness(from: memberSetting)
        let evaluatedAt = todayISO()

        // Preload sessions once for all exercises.
        let sessions = try performanceDataAccess.fetchSessions(memberId: memberId)
            .filter { $0.deletedAt == nil }
        var entriesByExercise: [UUID: [(sessionDate: Date, sets: [ModelSet])]] = [:]
        for session in sessions {
            let entries = try performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
                .filter { $0.deletedAt == nil }
            for entry in entries {
                let sets = try performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                    .filter { $0.deletedAt == nil }
                guard !sets.isEmpty else { continue }
                entriesByExercise[entry.exerciseId, default: []].append((session.date, sets))
            }
        }

        var manualsByExercise: [UUID: [PersonalBestModel]] = [:]
        for exercise in exercises {
            let manuals = try performanceDataAccess.fetchAllPBs(
                memberId: memberId,
                exerciseId: exercise.id
            ).filter { $0.entryType == .manualEntry && $0.deletedAt == nil }
            if !manuals.isEmpty {
                manualsByExercise[exercise.id] = manuals
            }
        }

        let resetsDescriptor = FetchDescriptor<ExerciseResetModel>(
            predicate: #Predicate { $0.memberId == memberId }
        )
        let resetISOByExercise: [UUID: String] = Dictionary(
            uniqueKeysWithValues: try contextFetchResets(
                descriptor: resetsDescriptor,
                context: modelContext
            )
        )

        var results: [PersonalBestModel] = []
        let order: (UUID) -> Int = { id in
            exercises.first { $0.id == id }?.displayOrder ?? Int.max
        }
        for exercise in exercises {
            guard let rule = exercise.pbRule else { continue }
            var records: [PBDerivation.Record] = []
            for batch in entriesByExercise[exercise.id] ?? [] {
                for set in batch.sets {
                    records.append(
                        PBDerivation.Record(
                            id: set.id.uuidString,
                            achievedAt: PBDerivation.formatISODate(batch.sessionDate),
                            weight: set.weight,
                            reps: set.reps,
                            time: set.time,
                            distance: set.distance,
                            entryKind: "set"
                        )
                    )
                }
            }
            for pb in manualsByExercise[exercise.id] ?? [] {
                records.append(
                    PBDerivation.Record(
                        id: pb.id.uuidString,
                        achievedAt: pb.achievedAt.map(PBDerivation.formatISODate),
                        weight: pb.weight,
                        reps: pb.reps,
                        time: pb.time,
                        distance: pb.distance,
                        entryKind: "manual"
                    )
                )
            }

            let derived = PBDerivation.derivePBs(
                rule: rule,
                records: records,
                staleness: staleness,
                resetAt: resetISOByExercise[exercise.id],
                evaluatedAt: evaluatedAt
            )
            if let current = derived.currentPB {
                results.append(
                    personalBest(from: current, memberId: memberId, exerciseId: exercise.id)
                )
            }
        }

        return results.sorted { order($0.exerciseId) < order($1.exerciseId) }
    }

    /// Re-derive current PB after hypothetically removing records (delete confirmation).
    static func deriveCurrentPBExcluding(
        memberId: UUID,
        exercise: ExerciseModel,
        performanceDataAccess: PerformanceDataAccess,
        modelContext: ModelContext,
        excludingRecordIds: Set<String>,
        excludingSetIds: Set<UUID>,
        evaluatedAt: String = todayISO()
    ) throws -> PersonalBestModel? {
        guard let rule = exercise.pbRule else { return nil }

        let memberSetting = try MemberState.stalenessSetting(in: modelContext, memberId: memberId)
        let staleness = staleness(from: memberSetting)
        var records = try records(
            memberId: memberId,
            exerciseId: exercise.id,
            performanceDataAccess: performanceDataAccess
        )
        records.removeAll { record in
            excludingRecordIds.contains(record.id) ||
                (record.entryKind == "set" && excludingSetIds.contains(UUID(uuidString: record.id) ?? UUID()))
        }

        let resetISO = try resetAtISO(
            memberId: memberId,
            exerciseId: exercise.id,
            in: modelContext
        )
        let derived = PBDerivation.derivePBs(
            rule: rule,
            records: records,
            staleness: staleness,
            resetAt: resetISO,
            evaluatedAt: evaluatedAt
        )
        return derived.currentPB.map {
            personalBest(from: $0, memberId: memberId, exerciseId: exercise.id)
        }
    }

    private static func contextFetchResets(
        descriptor: FetchDescriptor<ExerciseResetModel>,
        context: ModelContext
    ) throws -> [(UUID, String)] {
        try context.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .map { ($0.exerciseId, PBDerivation.formatISODate($0.resetAt)) }
    }
}
