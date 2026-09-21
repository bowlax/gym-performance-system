import Foundation
import Testing
@testable import GymPerformance

struct SyncPayloadMapperTests {
    @Test
    func sessionRowMapsCoreFields() {
        let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let deviceId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let sessionId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let sessionDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
        let syncedAt = Date(timeIntervalSince1970: 1_735_776_000)

        let session = SessionModel(
            id: sessionId,
            memberId: memberId,
            date: sessionDate,
            notes: "felt good",
            caloriesBurned: 420
        )

        let row = SyncPayloadMapper.sessionRow(session, gymId: gymId, deviceId: deviceId, syncedAt: syncedAt)

        #expect(row["id"] as? String == sessionId.uuidString)
        #expect(row["gym_id"] as? String == gymId.uuidString)
        #expect(row["member_id"] as? String == memberId.uuidString)
        #expect(row["date"] as? String == "2025-01-01")
        #expect(row["notes"] as? String == "felt good")
        #expect(row["calories_burned"] as? Int == 420)
        #expect(row["source_device_id"] as? String == deviceId.uuidString)
    }

    @Test
    func setRowUsesTimeSecondsColumnName() {
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let deviceId = UUID()
        let entryId = UUID()
        let set = ModelSet(exerciseEntryId: entryId, weight: 80, reps: 5, time: 92.5)

        let row = SyncPayloadMapper.setRow(set, gymId: gymId, deviceId: deviceId, syncedAt: Date())

        #expect(row["time_seconds"] as? Double == 92.5)
        #expect(row["weight"] as? Double == 80)
        #expect(row["reps"] as? Int == 5)
    }

    @Test
    func personalBestRowMapsNullAchievedAt() {
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let deviceId = UUID()
        let pb = PersonalBestModel(
            memberId: UUID(),
            exerciseId: UUID(),
            weight: 100,
            reps: 5,
            achievedAt: nil,
            entryType: .manualEntry
        )

        let row = SyncPayloadMapper.personalBestRow(
            pb,
            gymId: gymId,
            deviceId: deviceId,
            syncedAt: Date()
        )

        #expect(row["achieved_at"] is NSNull)
    }

    @Test
    func sessionRowMapsDeletedAtTombstone() {
        let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let deletedAt = Date(timeIntervalSince1970: 1_735_776_000)
        let session = SessionModel(
            memberId: memberId,
            date: Date(timeIntervalSince1970: 1_735_689_600),
            deletedAt: deletedAt
        )
        let row = SyncPayloadMapper.sessionRow(
            session,
            gymId: gymId,
            deviceId: UUID(),
            syncedAt: deletedAt
        )
        #expect(row["deleted_at"] is String)
    }

    @Test
    func memberSettingsPatchMapsStalenessOnly() {
        let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let deviceId = UUID()
        let member = UserIdentityModel(id: memberId, role: .member, displayName: "Lee")

        let row = SyncPayloadMapper.memberSettingsPatch(member, deviceId: deviceId, syncedAt: Date())

        #expect(row["staleness_enabled"] as? Bool == false)
        #expect(row["staleness_periods"] as? Int == 2)
        #expect(row["staleness_unit"] as? String == "quarter")
        #expect(row["id"] == nil)
        #expect(row["gym_id"] == nil)
        #expect(row["teamup_customer_id"] == nil)
        #expect(row["auth_user_id"] == nil)
        #expect(row["teamup_email"] == nil)
        #expect(row["teamup_roster_id"] == nil)
        #expect(row["log_reminder_email_opted_out_at"] == nil)
        #expect(row["source_device_id"] as? String == deviceId.uuidString)
    }

    @Test
    func logReminderEmailsPatchClearsOptOutWhenEnabled() {
        let deviceId = UUID()
        let now = Date(timeIntervalSince1970: 1_735_776_000)
        let row = SyncPayloadMapper.logReminderEmailsPatch(
            enabled: true,
            deviceId: deviceId,
            now: now
        )

        #expect(row["log_reminder_email_opted_out_at"] is NSNull)
        #expect(row["source_device_id"] as? String == deviceId.uuidString)
        #expect(row["staleness_enabled"] == nil)
    }

    @Test
    func logReminderEmailsPatchSetsTimestampWhenDisabled() {
        let now = Date(timeIntervalSince1970: 1_735_776_000)
        let row = SyncPayloadMapper.logReminderEmailsPatch(
            enabled: false,
            deviceId: UUID(),
            now: now
        )

        #expect(row["log_reminder_email_opted_out_at"] is String)
        #expect(row["updated_at"] as? String == row["log_reminder_email_opted_out_at"] as? String)
        #expect(row["synced_at"] as? String == row["updated_at"] as? String)
    }

    @Test
    func exerciseResetRowMapsCalendarDate() {
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let deviceId = UUID()
        let resetAt = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
        let reset = ExerciseResetModel(
            memberId: UUID(),
            exerciseId: UUID(),
            resetAt: resetAt
        )

        let row = SyncPayloadMapper.exerciseResetRow(
            reset,
            gymId: gymId,
            deviceId: deviceId,
            syncedAt: Date()
        )

        #expect(row["reset_at"] as? String == "2025-01-01")
        #expect(row["gym_id"] as? String == gymId.uuidString)
    }
}
