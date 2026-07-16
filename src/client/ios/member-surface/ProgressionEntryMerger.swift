import Foundation

enum ProgressionEntryMerger {
    static func merge(
        sessionHistory: [ExerciseSetSummary],
        personalBests: [PersonalBestModel],
        exercise: ExerciseModel,
        from: Date,
        badgeIds: Set<String> = [],
        resetAt: Date? = nil
    ) -> [ProgressionEntry] {
        var merged: [ProgressionEntry] = []
        var representedSetIds = Set<UUID>()

        let pbBySetId = personalBests.reduce(into: [UUID: UUID]()) { result, pb in
            guard let setId = pb.setId else { return }
            if let existingId = result[setId],
               let existing = personalBests.first(where: { $0.id == existingId }),
               let pbDate = pb.achievedAt,
               let existingDate = existing.achievedAt,
               pbDate < existingDate {
                return
            }
            result[setId] = pb.id
        }

        for summary in sessionHistory {
            representedSetIds.insert(summary.set.id)
            let personalBestId = pbBySetId[summary.set.id]
            let isPB = !badgeIds.isEmpty
                ? badgeIds.contains(summary.set.id.uuidString)
                : summary.isPB
            merged.append(
                ProgressionEntry(
                    id: summary.set.id,
                    date: summary.sessionDate,
                    formattedValue: PBFormatter.formatSet(summary.set, exercise: exercise),
                    chartValue: PBFormatter.chartValue(set: summary.set, exercise: exercise),
                    isPB: isPB,
                    isResetMarker: false,
                    setId: summary.set.id,
                    personalBestId: personalBestId
                )
            )
        }

        // Undated manuals never appear in history (#28).
        for pb in personalBests {
            guard let achievedAt = pb.achievedAt, achievedAt >= from else { continue }
            if pb.entryType == .sessionDerived {
                continue
            }
            if let setId = pb.setId, representedSetIds.contains(setId) {
                continue
            }

            let isPB = !badgeIds.isEmpty
                ? badgeIds.contains(pb.id.uuidString)
                : true
            merged.append(
                ProgressionEntry(
                    id: pb.id,
                    date: achievedAt,
                    formattedValue: PBFormatter.formatPB(pb, exercise: exercise),
                    chartValue: PBFormatter.chartValue(pb: pb, exercise: exercise),
                    isPB: isPB,
                    isResetMarker: false,
                    setId: pb.setId,
                    personalBestId: pb.id
                )
            )
        }

        if let resetAt, resetAt >= from {
            merged.append(
                ProgressionEntry(
                    id: UUID(),
                    date: resetAt,
                    formattedValue: "Reset",
                    chartValue: 0,
                    isPB: false,
                    isResetMarker: true,
                    setId: nil,
                    personalBestId: nil
                )
            )
        }

        return merged.sorted { $0.date < $1.date }
    }
}
