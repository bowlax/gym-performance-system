import Foundation

enum SyncPayloadMapper {
    private static let calendarDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func sessionRow(
        _ session: SessionModel,
        gymId: UUID,
        deviceId: UUID,
        syncedAt: Date
    ) -> [String: Any] {
        [
            "id": session.id.uuidString,
            "gym_id": gymId.uuidString,
            "member_id": session.memberId.uuidString,
            "date": calendarDateString(session.date),
            "notes": jsonValue(session.notes),
            "calories_burned": jsonValue(session.caloriesBurned),
            "created_at": iso8601(session.createdAt),
            "updated_at": iso8601(session.updatedAt),
            "synced_at": iso8601(syncedAt),
            "source_device_id": deviceId.uuidString,
            "deleted_at": jsonValue(session.deletedAt.map(iso8601)),
        ]
    }

    static func exerciseEntryRow(
        _ entry: ExerciseEntryModel,
        gymId: UUID,
        deviceId: UUID,
        syncedAt: Date
    ) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "gym_id": gymId.uuidString,
            "session_id": entry.sessionId.uuidString,
            "exercise_id": entry.exerciseId.uuidString,
            "created_at": iso8601(entry.createdAt),
            "updated_at": iso8601(entry.updatedAt),
            "synced_at": iso8601(syncedAt),
            "source_device_id": deviceId.uuidString,
            "deleted_at": jsonValue(entry.deletedAt.map(iso8601)),
        ]
    }

    static func setRow(
        _ set: ModelSet,
        gymId: UUID,
        deviceId: UUID,
        syncedAt: Date
    ) -> [String: Any] {
        [
            "id": set.id.uuidString,
            "gym_id": gymId.uuidString,
            "exercise_entry_id": set.exerciseEntryId.uuidString,
            "weight": jsonValue(set.weight),
            "reps": jsonValue(set.reps),
            "time_seconds": jsonValue(set.time),
            "distance": jsonValue(set.distance),
            "created_at": iso8601(set.createdAt),
            "updated_at": iso8601(set.updatedAt),
            "synced_at": iso8601(syncedAt),
            "source_device_id": deviceId.uuidString,
            "deleted_at": jsonValue(set.deletedAt.map(iso8601)),
        ]
    }

    static func personalBestRow(
        _ pb: PersonalBestModel,
        gymId: UUID,
        deviceId: UUID,
        syncedAt: Date
    ) -> [String: Any] {
        [
            "id": pb.id.uuidString,
            "gym_id": gymId.uuidString,
            "member_id": pb.memberId.uuidString,
            "exercise_id": pb.exerciseId.uuidString,
            "set_id": jsonValue(pb.setId?.uuidString),
            "weight": jsonValue(pb.weight),
            "reps": jsonValue(pb.reps),
            "time_seconds": jsonValue(pb.time),
            "distance": jsonValue(pb.distance),
            "achieved_at": jsonValue(pb.achievedAt.map(calendarDateString)),
            "entry_type": pb.entryType.rawValue,
            "created_at": iso8601(pb.createdAt),
            "updated_at": iso8601(pb.effectiveUpdatedAt),
            "synced_at": iso8601(syncedAt),
            "source_device_id": deviceId.uuidString,
            "deleted_at": jsonValue(pb.deletedAt.map(iso8601)),
        ]
    }

    /// Settings-only PATCH body for `members`. Must not include broker-owned
    /// identity fields (`id`, `gym_id`, `teamup_customer_id`, `auth_user_id`);
    /// filter is `id=eq.{jwt member_id}`. Devices never establish Auth users.
    static func memberSettingsPatch(
        _ member: UserIdentityModel,
        deviceId: UUID,
        syncedAt: Date
    ) -> [String: Any] {
        [
            "staleness_enabled": member.stalenessEnabled,
            "staleness_periods": member.stalenessPeriods,
            "staleness_unit": member.stalenessUnit.rawValue,
            "updated_at": iso8601(member.updatedAt),
            "synced_at": iso8601(syncedAt),
            "source_device_id": deviceId.uuidString,
        ]
    }

    static func exerciseResetRow(
        _ reset: ExerciseResetModel,
        gymId: UUID,
        deviceId: UUID,
        syncedAt: Date
    ) -> [String: Any] {
        [
            "id": reset.id.uuidString,
            "gym_id": gymId.uuidString,
            "member_id": reset.memberId.uuidString,
            "exercise_id": reset.exerciseId.uuidString,
            "reset_at": calendarDateString(reset.resetAt),
            "created_at": iso8601(reset.createdAt),
            "updated_at": iso8601(reset.updatedAt),
            "synced_at": iso8601(syncedAt),
            "source_device_id": deviceId.uuidString,
            "deleted_at": jsonValue(reset.deletedAt.map(iso8601)),
        ]
    }

    private static func jsonValue<T>(_ value: T?) -> Any {
        value ?? NSNull()
    }

    private static func calendarDateString(_ date: Date) -> String {
        calendarDateFormatter.string(from: date)
    }

    private static func iso8601(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}
