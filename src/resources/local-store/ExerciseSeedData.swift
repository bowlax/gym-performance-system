import Foundation

extension ExerciseModel {

    static var seedData: [ExerciseModel] {
        [
            // MARK: -- Fixed Rep Barbell Lifts

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Overhead Press",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 1
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Free Squat",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 2
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Box Squat",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                displayOrder: 3
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                name: "Bench Press 3x5",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 4
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                name: "Bench Press 1x5",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                displayOrder: 5
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                name: "Straight Bar Deadlift",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 6
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                name: "Trap Bar Deadlift",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                displayOrder: 7
            ),

            // MARK: -- Variable Rep Dumbbell and Bodyweight

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
                name: "45-Degree Dumbbell Press",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 8
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
                name: "Flat Dumbbell Press",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 9
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                name: "Chest Dumbbell Row",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 10
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                name: "Split Squat Dumbbell",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 11
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                name: "One Arm Dumbbell Row",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 12
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
                name: "Push-ups",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 13
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
                name: "Pulldown",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 14
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
                name: "Cable Row",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 15
            ),

            // MARK: -- Reps Only

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
                name: "Chin-ups",
                category: .pbExercise,
                measurementType: .repsOnly,
                pbRule: .mostReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 16
            ),

            // MARK: -- Weight and Time

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
                name: "Plank",
                category: .pbExercise,
                measurementType: .weightAndTime,
                pbRule: .heaviestWeight,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 17
            ),

            // MARK: -- Timed

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
                name: "Ski 500m",
                category: .pbExercise,
                measurementType: .timeOnly,
                pbRule: .fastestTime,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 18
            ),

            // MARK: -- Distance

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
                name: "Bike 60s",
                category: .pbExercise,
                measurementType: .distanceOnly,
                pbRule: .longestDistance,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 19
            )
        ]
    }
}
