import Foundation

/// Progression lifetime element visibility (#28).
/// Show iff lifetime strictly beats current under the exercise PB rule.
enum LifetimePBVisibility {
    static func shouldShow(
        lifetime: PersonalBestModel?,
        current: PersonalBestModel?,
        rule: PBRule?
    ) -> Bool {
        guard let rule else { return false }
        return PBDerivation.shouldShowLifetimePB(
            lifetime: lifetime.map(asRecord),
            current: current.map(asRecord),
            rule: rule
        )
    }

    private static func asRecord(_ pb: PersonalBestModel) -> PBDerivation.Record {
        PBDerivation.Record(
            id: pb.id.uuidString,
            achievedAt: pb.achievedAt.map(PBDerivation.formatISODate),
            weight: pb.weight,
            reps: pb.reps,
            time: pb.time,
            distance: pb.distance,
            entryKind: pb.entryType == .manualEntry ? "manual" : "set"
        )
    }
}
