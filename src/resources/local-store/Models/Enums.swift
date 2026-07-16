import Foundation

enum Role: String, Codable {
    case member
    case coach
    case owner
}

enum ExerciseCategory: String, Codable {
    case pbExercise
    case conditioning
}

enum MeasurementType: String, Codable {
    case weightAndReps
    case timeOnly
    case distanceOnly
    case repsOnly
    case weightAndDistance
    case weightAndTime
}

enum PBRule: String, Codable {
    case heaviestWeightAtReps
    case heaviestWeight
    case fastestTime
    case longestDistance
    case mostReps
    case bestWeightAndReps
}

enum PBEntryType: String, Codable {
    case sessionDerived
    case manualEntry
}

/// Cloud / local storage unit for member staleness windows (#28).
/// Derivation vectors use plural (`quarters` / `months`); map at wire time.
enum StalenessPeriodUnit: String, Codable, Sendable {
    case quarter
    case month
}
