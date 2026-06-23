import Foundation

enum ProgressionEntryMerger {
    static func merge(
        sessionHistory: [ExerciseSetSummary],
        personalBests: [PersonalBestModel],
        exercise: ExerciseModel,
        from: Date
    ) -> [ProgressionEntry] {
        var merged: [ProgressionEntry] = []
        var representedSetIds = Set<UUID>()

        let pbBySetId = personalBests.reduce(into: [UUID: UUID]()) { result, pb in
            guard let setId = pb.setId else { return }
            if let existingId = result[setId],
               let existing = personalBests.first(where: { $0.id == existingId }),
               pb.achievedAt < existing.achievedAt || (!pb.isCurrent && existing.isCurrent) {
                return
            }
            result[setId] = pb.id
        }
        let pbById = Dictionary(uniqueKeysWithValues: personalBests.map { ($0.id, $0) })

        for summary in sessionHistory {
            representedSetIds.insert(summary.set.id)
            let personalBestId = pbBySetId[summary.set.id]
            let linkedPB = personalBestId.flatMap { pbById[$0] }
            merged.append(
                ProgressionEntry(
                    id: summary.set.id,
                    date: summary.sessionDate,
                    formattedValue: PBFormatter.formatSet(summary.set, exercise: exercise),
                    chartValue: PBFormatter.chartValue(set: summary.set, exercise: exercise),
                    isPB: summary.isPB,
                    wasReset: linkedPB?.wasReset ?? false,
                    setId: summary.set.id,
                    personalBestId: personalBestId
                )
            )
        }

        for pb in personalBests where pb.achievedAt >= from {
            if pb.entryType == .sessionDerived {
                continue
            }
            if let setId = pb.setId, representedSetIds.contains(setId) {
                continue
            }

            merged.append(
                ProgressionEntry(
                    id: pb.id,
                    date: pb.achievedAt,
                    formattedValue: PBFormatter.formatPB(pb, exercise: exercise),
                    chartValue: PBFormatter.chartValue(pb: pb, exercise: exercise),
                    isPB: true,
                    wasReset: pb.wasReset,
                    setId: pb.setId,
                    personalBestId: pb.id
                )
            )
        }

        return merged.sorted { $0.date < $1.date }
    }
}
