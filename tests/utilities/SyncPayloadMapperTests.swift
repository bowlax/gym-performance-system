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
}
