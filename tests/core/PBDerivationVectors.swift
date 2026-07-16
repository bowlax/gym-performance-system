import Foundation
@testable import GymPerformance

// MARK: - Expiry vectors

struct PBExpiryVector: Codable, Sendable {
    let id: String
    let description: String
    let achievedAt: String
    let compareAchievedAt: String?
    let staleness: PBDerivation.StalenessSetting
    let evaluatedAt: String
    let expectedExpiryAt: String?
    let expectedFresh: Bool
    let expectedCompareExpiryAt: String?
    let expectedCompareFresh: Bool?
}

private struct PBExpiryVectorFile: Codable {
    let schemaVersion: Int
    let vectors: [PBExpiryVector]
}

// MARK: - Derivation vectors

struct PBDerivationVectorRecord: Codable, Sendable {
    let id: String
    let achievedAt: String?
    let weight: Double?
    let reps: Int?
    let time: Double?
    let distance: Double?
    let entryKind: String?
}

struct PBDerivationVector: Codable, Sendable {
    let id: String
    let description: String
    let rule: String
    let staleness: PBDerivation.StalenessSetting
    let resetAt: String?
    let evaluatedAt: String
    let records: [PBDerivationVectorRecord]
    let expectedCurrentId: String?
    let expectedLifetimeId: String?
}

private struct PBDerivationVectorFile: Codable {
    let schemaVersion: Int
    let vectors: [PBDerivationVector]
}

// MARK: - Badge vectors

struct PBBadgeVector: Codable, Sendable {
    let id: String
    let description: String
    let rule: String
    let records: [PBDerivationVectorRecord]
    let expectedBadgedIds: [String]
}

private struct PBBadgeVectorFile: Codable {
    let schemaVersion: Int
    let vectors: [PBBadgeVector]
}

// MARK: - Lifetime visibility vectors

struct PBLifetimeVisibilityMeasurement: Codable, Sendable {
    let weight: Double?
    let reps: Int?
    let time: Double?
    let distance: Double?
}

struct PBLifetimeVisibilityVector: Codable, Sendable {
    let id: String
    let description: String
    let rule: String
    let current: PBLifetimeVisibilityMeasurement?
    let lifetime: PBLifetimeVisibilityMeasurement?
    let expectedShow: Bool
}

private struct PBLifetimeVisibilityVectorFile: Codable {
    let schemaVersion: Int
    let vectors: [PBLifetimeVisibilityVector]
}

// MARK: - Loaders

enum PBDerivationVectorLoader {
    private static let vectorsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("vectors")

    static func loadExpiry() throws -> [PBExpiryVector] {
        let url = vectorsDirectory.appendingPathComponent("pb-expiry-vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PBExpiryVectorFile.self, from: data).vectors
    }

    static func loadDerivation() throws -> [PBDerivationVector] {
        let url = vectorsDirectory.appendingPathComponent("pb-derivation-vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PBDerivationVectorFile.self, from: data).vectors
    }

    static func loadBadges() throws -> [PBBadgeVector] {
        let url = vectorsDirectory.appendingPathComponent("pb-badge-vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PBBadgeVectorFile.self, from: data).vectors
    }

    static func loadLifetimeVisibility() throws -> [PBLifetimeVisibilityVector] {
        let url = vectorsDirectory.appendingPathComponent("pb-lifetime-visibility-vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PBLifetimeVisibilityVectorFile.self, from: data).vectors
    }
}

// MARK: - Helpers

enum PBDerivationVectorSupport {
    static func pbRule(from raw: String) -> PBRule {
        guard let rule = PBRule(rawValue: raw) else {
            fatalError("Unknown PB rule: \(raw)")
        }
        return rule
    }

    static func records(from vectorRecords: [PBDerivationVectorRecord]) -> [PBDerivation.Record] {
        vectorRecords.map { record in
            PBDerivation.Record(
                id: record.id,
                achievedAt: record.achievedAt,
                weight: record.weight,
                reps: record.reps,
                time: record.time,
                distance: record.distance,
                entryKind: record.entryKind
            )
        }
    }

    static func visibilityRecord(
        from measurement: PBLifetimeVisibilityMeasurement?,
        id: String
    ) -> PBDerivation.Record? {
        guard let measurement else { return nil }
        return PBDerivation.Record(
            id: id,
            achievedAt: nil,
            weight: measurement.weight,
            reps: measurement.reps,
            time: measurement.time,
            distance: measurement.distance,
            entryKind: "manual"
        )
    }
}
