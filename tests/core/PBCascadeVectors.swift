import Foundation
@testable import GymPerformance

struct PBCascadeRecord: Codable, Sendable {
    let id: String
    let weight: Double?
    let reps: Int?
    let time: Double?
    let distance: Double?
    let achievedAt: String?
    let wasReset: Bool?
    let setId: String?
}

struct PBCascadeVector: Codable, Sendable {
    let id: String
    let description: String
    let rule: String
    let exerciseName: String
    let targetReps: Int?
    let minimumReps: Int?
    let records: [PBCascadeRecord]
    let excludingIds: [String]?
    let excludingSetIds: [String]?
    let expectedCurrentId: String?
}

private struct PBCascadeVectorFile: Codable {
    let schemaVersion: Int
    let vectors: [PBCascadeVector]
}

enum PBCascadeVectorLoader {
    static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("vectors/pb-cascade-vectors.json")

    static func load() throws -> [PBCascadeVector] {
        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(PBCascadeVectorFile.self, from: data)
        return file.vectors
    }
}

enum PBCascadeVectorRunner {
    private static let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    static func selectedRecordId(_ vector: PBCascadeVector) -> String? {
        let exercise = exercise(named: vector.exerciseName)
        let built = buildRecords(vector.records, exerciseId: exercise.id)
        let excludingIds = Set(
            (vector.excludingIds ?? []).compactMap { built.idByRecordId[$0]?.id }
        )
        let excludingSetIds = Set(
            (vector.excludingSetIds ?? []).compactMap { built.setIdByRecordId[$0] }
        )

        guard let selected = PersonalBestRanking.bestRestorable(
            from: built.models,
            exercise: exercise,
            excludingIds: excludingIds,
            excludingSetIds: excludingSetIds
        ) else {
            return nil
        }

        return built.recordIdByModelId[selected.id]
    }

    private struct BuiltRecords {
        let models: [PersonalBestModel]
        let idByRecordId: [String: PersonalBestModel]
        let recordIdByModelId: [UUID: String]
        let setIdByRecordId: [String: UUID]
    }

    private static func buildRecords(
        _ records: [PBCascadeRecord],
        exerciseId: UUID
    ) -> BuiltRecords {
        var models: [PersonalBestModel] = []
        var idByRecordId: [String: PersonalBestModel] = [:]
        var recordIdByModelId: [UUID: String] = [:]
        var setIdByRecordId: [String: UUID] = [:]

        for record in records {
            let modelId = UUID()
            let setId = record.setId.map { _ in UUID() }
            if let setId, let setRecordId = record.setId {
                setIdByRecordId[setRecordId] = setId
            }

            let achievedAt = record.achievedAt.flatMap(isoDate(from:)) ?? Date()
            let model = PersonalBestModel(
                id: modelId,
                memberId: memberId,
                exerciseId: exerciseId,
                setId: setId,
                weight: record.weight,
                reps: record.reps,
                time: record.time,
                distance: record.distance,
                achievedAt: achievedAt,
                isCurrent: false,
                wasReset: record.wasReset ?? false
            )

            models.append(model)
            idByRecordId[record.id] = model
            recordIdByModelId[modelId] = record.id
        }

        return BuiltRecords(
            models: models,
            idByRecordId: idByRecordId,
            recordIdByModelId: recordIdByModelId,
            setIdByRecordId: setIdByRecordId
        )
    }

    private static func exercise(named name: String) -> ExerciseModel {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise for cascade vector: \(name)")
        }
        return exercise
    }

    private static func isoDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
