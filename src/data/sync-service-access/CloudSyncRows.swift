import Foundation

/// Cloud rows returned by PostgREST pull queries. `synced_at` is the cloud-authoritative watermark field.
struct CloudSessionRow: Equatable, Sendable {
    var id: UUID
    var gymId: UUID
    var memberId: UUID
    var date: Date
    var notes: String?
    var caloriesBurned: Int?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?
    var sourceDeviceId: UUID?
}

struct CloudExerciseEntryRow: Equatable, Sendable {
    var id: UUID
    var gymId: UUID
    var sessionId: UUID
    var exerciseId: UUID
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?
    var sourceDeviceId: UUID?
}

struct CloudSetRow: Equatable, Sendable {
    var id: UUID
    var gymId: UUID
    var exerciseEntryId: UUID
    var weight: Double?
    var reps: Int?
    var timeSeconds: Double?
    var distance: Double?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?
    var sourceDeviceId: UUID?
}

struct CloudPersonalBestRow: Equatable, Sendable {
    var id: UUID
    var gymId: UUID
    var memberId: UUID
    var exerciseId: UUID
    var setId: UUID?
    var weight: Double?
    var reps: Int?
    var timeSeconds: Double?
    var distance: Double?
    var achievedAt: Date?
    var entryType: String
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?
    var sourceDeviceId: UUID?
}

struct CloudMemberRow: Equatable, Sendable {
    var id: UUID
    var gymId: UUID
    var displayName: String
    var stalenessEnabled: Bool
    var stalenessPeriods: Int
    var stalenessUnit: String
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var sourceDeviceId: UUID?
}

struct CloudExerciseResetRow: Equatable, Sendable {
    var id: UUID
    var gymId: UUID
    var memberId: UUID
    var exerciseId: UUID
    var resetAt: Date
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?
    var sourceDeviceId: UUID?
}

enum CloudRowDecoder {
    private static let calendarDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoWithoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func decodeSessions(from data: Data) throws -> [CloudSessionRow] {
        let objects = try decodeObjectArray(data)
        return try objects.map { object in
            CloudSessionRow(
                id: try uuid(object, "id"),
                gymId: try uuid(object, "gym_id"),
                memberId: try uuid(object, "member_id"),
                date: try calendarDate(object, "date"),
                notes: object["notes"] as? String,
                caloriesBurned: intValue(object["calories_burned"]),
                createdAt: try date(object, "created_at"),
                updatedAt: try date(object, "updated_at"),
                syncedAt: optionalDate(object, "synced_at"),
                deletedAt: optionalDate(object, "deleted_at"),
                sourceDeviceId: optionalUUID(object, "source_device_id")
            )
        }
    }

    static func decodeExerciseEntries(from data: Data) throws -> [CloudExerciseEntryRow] {
        let objects = try decodeObjectArray(data)
        return try objects.map { object in
            CloudExerciseEntryRow(
                id: try uuid(object, "id"),
                gymId: try uuid(object, "gym_id"),
                sessionId: try uuid(object, "session_id"),
                exerciseId: try uuid(object, "exercise_id"),
                createdAt: try date(object, "created_at"),
                updatedAt: try date(object, "updated_at"),
                syncedAt: optionalDate(object, "synced_at"),
                deletedAt: optionalDate(object, "deleted_at"),
                sourceDeviceId: optionalUUID(object, "source_device_id")
            )
        }
    }

    static func decodeSets(from data: Data) throws -> [CloudSetRow] {
        let objects = try decodeObjectArray(data)
        return try objects.map { object in
            CloudSetRow(
                id: try uuid(object, "id"),
                gymId: try uuid(object, "gym_id"),
                exerciseEntryId: try uuid(object, "exercise_entry_id"),
                weight: doubleValue(object["weight"]),
                reps: intValue(object["reps"]),
                timeSeconds: doubleValue(object["time_seconds"]),
                distance: doubleValue(object["distance"]),
                createdAt: try date(object, "created_at"),
                updatedAt: try date(object, "updated_at"),
                syncedAt: optionalDate(object, "synced_at"),
                deletedAt: optionalDate(object, "deleted_at"),
                sourceDeviceId: optionalUUID(object, "source_device_id")
            )
        }
    }

    static func decodePersonalBests(from data: Data) throws -> [CloudPersonalBestRow] {
        let objects = try decodeObjectArray(data)
        return try objects.map { object in
            CloudPersonalBestRow(
                id: try uuid(object, "id"),
                gymId: try uuid(object, "gym_id"),
                memberId: try uuid(object, "member_id"),
                exerciseId: try uuid(object, "exercise_id"),
                setId: optionalUUID(object, "set_id"),
                weight: doubleValue(object["weight"]),
                reps: intValue(object["reps"]),
                timeSeconds: doubleValue(object["time_seconds"]),
                distance: doubleValue(object["distance"]),
                achievedAt: try optionalCalendarDate(object, "achieved_at"),
                entryType: (object["entry_type"] as? String) ?? PBEntryType.manualEntry.rawValue,
                createdAt: try date(object, "created_at"),
                updatedAt: try date(object, "updated_at"),
                syncedAt: optionalDate(object, "synced_at"),
                deletedAt: optionalDate(object, "deleted_at"),
                sourceDeviceId: optionalUUID(object, "source_device_id")
            )
        }
    }

    static func decodeMembers(from data: Data) throws -> [CloudMemberRow] {
        let objects = try decodeObjectArray(data)
        return try objects.map { object in
            CloudMemberRow(
                id: try uuid(object, "id"),
                gymId: try uuid(object, "gym_id"),
                displayName: (object["display_name"] as? String) ?? "Member",
                stalenessEnabled: (object["staleness_enabled"] as? Bool) ?? false,
                stalenessPeriods: intValue(object["staleness_periods"]) ?? 2,
                stalenessUnit: (object["staleness_unit"] as? String) ?? StalenessPeriodUnit.quarter.rawValue,
                createdAt: try date(object, "created_at"),
                updatedAt: try date(object, "updated_at"),
                syncedAt: optionalDate(object, "synced_at"),
                sourceDeviceId: optionalUUID(object, "source_device_id")
            )
        }
    }

    static func decodeExerciseResets(from data: Data) throws -> [CloudExerciseResetRow] {
        let objects = try decodeObjectArray(data)
        return try objects.map { object in
            CloudExerciseResetRow(
                id: try uuid(object, "id"),
                gymId: try uuid(object, "gym_id"),
                memberId: try uuid(object, "member_id"),
                exerciseId: try uuid(object, "exercise_id"),
                resetAt: try calendarDate(object, "reset_at"),
                createdAt: try date(object, "created_at"),
                updatedAt: try date(object, "updated_at"),
                syncedAt: optionalDate(object, "synced_at"),
                deletedAt: optionalDate(object, "deleted_at"),
                sourceDeviceId: optionalUUID(object, "source_device_id")
            )
        }
    }

    private static func decodeObjectArray(_ data: Data) throws -> [[String: Any]] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [[String: Any]] else {
            throw SyncError.pullFailed(table: "unknown", statusCode: -1, detail: "Expected JSON array")
        }
        return array
    }

    private static func uuid(_ object: [String: Any], _ key: String) throws -> UUID {
        guard let string = object[key] as? String, let value = UUID(uuidString: string) else {
            throw SyncError.pullFailed(table: key, statusCode: -1, detail: "Missing UUID \(key)")
        }
        return value
    }

    private static func optionalUUID(_ object: [String: Any], _ key: String) -> UUID? {
        guard let string = object[key] as? String else { return nil }
        return UUID(uuidString: string)
    }

    private static func date(_ object: [String: Any], _ key: String) throws -> Date {
        guard let string = object[key] as? String, let value = parseISO8601(string) else {
            throw SyncError.pullFailed(table: key, statusCode: -1, detail: "Missing date \(key)")
        }
        return value
    }

    private static func optionalDate(_ object: [String: Any], _ key: String) -> Date? {
        guard let string = object[key] as? String else { return nil }
        return parseISO8601(string)
    }

    private static func calendarDate(_ object: [String: Any], _ key: String) throws -> Date {
        guard let value = try optionalCalendarDate(object, key) else {
            throw SyncError.pullFailed(table: key, statusCode: -1, detail: "Missing calendar date \(key)")
        }
        return value
    }

    /// Null / missing calendar dates are allowed (undated manual PBs). Invalid
    /// non-null strings still fail the pull.
    private static func optionalCalendarDate(_ object: [String: Any], _ key: String) throws -> Date? {
        guard let raw = object[key], !(raw is NSNull) else { return nil }
        guard let string = raw as? String else {
            throw SyncError.pullFailed(table: key, statusCode: -1, detail: "Invalid calendar date \(key)")
        }
        if string.isEmpty { return nil }
        if let value = calendarDateFormatter.date(from: string) {
            return value
        }
        if let value = parseISO8601(string) {
            return Calendar(identifier: .gregorian).startOfDay(for: value)
        }
        throw SyncError.pullFailed(table: key, statusCode: -1, detail: "Invalid calendar date \(key)")
    }

    private static func parseISO8601(_ string: String) -> Date? {
        isoWithFractional.date(from: string) ?? isoWithoutFractional.date(from: string)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }
}
