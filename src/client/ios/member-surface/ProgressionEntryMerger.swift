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

        let pbBySetId = Dictionary(
            uniqueKeysWithValues: personalBests.compactMap { pb -> (UUID, UUID)? in
                guard let setId = pb.setId else { return nil }
                return (setId, pb.id)
            }
        )

        for summary in sessionHistory {
            representedSetIds.insert(summary.set.id)
            merged.append(
                ProgressionEntry(
                    id: summary.set.id,
                    date: summary.sessionDate,
                    formattedValue: PBFormatter.formatSet(summary.set, exercise: exercise),
                    chartValue: PBFormatter.chartValue(set: summary.set, exercise: exercise),
                    isPB: summary.isPB,
                    personalBestId: pbBySetId[summary.set.id]
                )
            )
        }

        for pb in personalBests where pb.achievedAt >= from {
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
                    personalBestId: pb.id
                )
            )
        }

        return merged.sorted { $0.date < $1.date }
    }
}
