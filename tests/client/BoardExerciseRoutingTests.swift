#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct BoardExerciseRoutingTests {
    private let exerciseId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000010")!
    private let currentPB = PersonalBestModel(
        memberId: UUID(),
        exerciseId: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000010")!,
        weight: 100,
        reps: 5,
        achievedAt: Date()
    )

    @Test
    func routesToProgressionWhenCurrentPBExists() {
        let destination = BoardExerciseRouting.destination(
            for: exerciseId,
            currentPBByExerciseId: [exerciseId: currentPB],
            exerciseIdsWithHistory: []
        )

        #expect(destination == .progression)
    }

    @Test
    func routesToProgressionWhenHistoryExistsWithoutCurrentPB() {
        let destination = BoardExerciseRouting.destination(
            for: exerciseId,
            currentPBByExerciseId: [:],
            exerciseIdsWithHistory: [exerciseId]
        )

        #expect(destination == .progression)
    }

    @Test
    func routesToManualEntryWhenNoHistoryExists() {
        let destination = BoardExerciseRouting.destination(
            for: exerciseId,
            currentPBByExerciseId: [:],
            exerciseIdsWithHistory: []
        )

        #expect(destination == .manualPBEntry)
    }
}
#endif
