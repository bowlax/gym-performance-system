import Foundation

enum PBFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    static func formatSet(_ set: ModelSet, exercise: ExerciseModel) -> String {
        formatValues(
            weight: set.weight,
            reps: set.reps,
            time: set.time,
            distance: set.distance,
            exercise: exercise
        )
    }

    static func formatPB(_ pb: PersonalBestModel, exercise: ExerciseModel) -> String {
        formatValues(
            weight: pb.weight,
            reps: pb.reps,
            time: pb.time,
            distance: pb.distance,
            exercise: exercise
        )
    }

    static func chartValue(set: ModelSet, exercise: ExerciseModel) -> Double {
        chartValue(
            weight: set.weight,
            reps: set.reps,
            time: set.time,
            distance: set.distance,
            exercise: exercise
        )
    }

    static func chartValue(pb: PersonalBestModel, exercise: ExerciseModel) -> Double {
        chartValue(
            weight: pb.weight,
            reps: pb.reps,
            time: pb.time,
            distance: pb.distance,
            exercise: exercise
        )
    }

    static func chartValue(
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?,
        exercise: ExerciseModel
    ) -> Double {
        switch exercise.measurementType {
        case .weightAndReps, .weightAndTime, .weightAndDistance:
            return weight ?? 0
        case .timeOnly:
            return time ?? 0
        case .distanceOnly:
            return distance ?? 0
        case .repsOnly:
            return Double(reps ?? 0)
        }
    }

    static func formatValues(
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?,
        exercise: ExerciseModel
    ) -> String {
        if exercise.name == "Cable Row" {
            return "\(trim(weight)) × \(reps ?? 0)"
        }

        switch exercise.measurementType {
        case .weightAndReps:
            return "\(trim(weight))kg × \(reps ?? 0)"
        case .weightAndTime:
            return "\(trim(weight))kg × \(rawSeconds(time))"
        case .timeOnly:
            return mmss(time)
        case .distanceOnly:
            return "\(Int(distance ?? 0))m"
        case .repsOnly:
            return "\(reps ?? 0) reps"
        case .weightAndDistance:
            return "\(trim(weight))kg × \(Int(distance ?? 0))m"
        }
    }

    static func trim(_ weight: Double?) -> String {
        guard let weight else { return "0" }
        return weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }

    static func rawSeconds(_ seconds: Double?) -> String {
        guard let seconds else { return "0s" }
        return "\(Int(seconds.rounded()))s"
    }

    static func mmss(_ seconds: Double?) -> String {
        guard let seconds else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func mmss(_ seconds: Int?) -> String {
        mmss(seconds.map(Double.init))
    }
}
