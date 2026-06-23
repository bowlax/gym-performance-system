import Foundation

enum BoardExerciseRouting {
    enum Destination {
        case progression
        case manualPBEntry
    }

    static func destination(
        for exerciseId: UUID,
        currentPBByExerciseId: [UUID: PersonalBestModel],
        exerciseIdsWithHistory: Set<UUID>
    ) -> Destination {
        if currentPBByExerciseId[exerciseId] != nil
            || exerciseIdsWithHistory.contains(exerciseId) {
            return .progression
        }
        return .manualPBEntry
    }
}
