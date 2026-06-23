#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct PersonalBestRankingTests {
    private let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    private func exercise(named name: String) -> ExerciseModel {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise: \(name)")
        }
        return exercise
    }

    @Test
    func selectsHighestWeightIgnoringResetRecords() {
        let squat = exercise(named: "Free Squat")
        let reset = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            weight: 100,
            reps: 5,
            achievedAt: Date(),
            isCurrent: false,
            wasReset: true
        )
        let best = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            weight: 80,
            reps: 5,
            achievedAt: Date().addingTimeInterval(-86_400),
            isCurrent: false
        )

        let selected = PersonalBestRanking.bestRestorable(
            from: [reset, best],
            exercise: squat
        )

        #expect(selected?.id == best.id)
    }

    @Test
    func selectsBestWeightNotMostRecentDate() {
        let squat = exercise(named: "Free Squat")
        let jan = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            weight: 80,
            reps: 5,
            achievedAt: Date(timeIntervalSince1970: 1_704_067_200)
        )
        let mar = PersonalBestModel(
            memberId: memberId,
            exerciseId: squat.id,
            weight: 70,
            reps: 5,
            achievedAt: Date(timeIntervalSince1970: 1_709_270_400)
        )

        let selected = PersonalBestRanking.best(from: [jan, mar], exercise: squat)
        #expect(selected?.id == jan.id)
    }
}
#endif
