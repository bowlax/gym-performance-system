import Foundation

/// Push-only, resumable first-connect upload of local member history to the cloud.
///
/// Upload order respects foreign keys: member settings (PATCH) → sessions →
/// exercise entries → sets → personal bests → exercise resets. Only dirty local
/// records are pushed. Successful batches set `syncedAt` so a retry after partial
/// failure does not duplicate rows (cloud upserts are idempotent on id).
/// Member settings never INSERT — broker create-or-adopt owns identity.
struct FirstConnectUploader {
    private let localDataAccess: SyncLocalDataAccess
    private let syncServiceAccess: SyncServiceAccess
    private let credentials: SyncCredentials
    private let batchSize: Int

    init(
        localDataAccess: SyncLocalDataAccess,
        syncServiceAccess: SyncServiceAccess,
        credentials: SyncCredentials,
        batchSize: Int = SyncConstants.uploadBatchSize
    ) {
        self.localDataAccess = localDataAccess
        self.syncServiceAccess = syncServiceAccess
        self.credentials = credentials
        self.batchSize = batchSize
    }

    func upload(memberId: UUID) async -> FirstConnectUploadResult {
        var counts = FirstConnectUploadCounts()

        do {
            counts.members = try await uploadMembers(memberId: memberId)
            counts.sessions = try await uploadSessions(memberId: memberId)
            counts.exerciseEntries = try await uploadExerciseEntries(memberId: memberId)
            counts.sets = try await uploadSets(memberId: memberId)
            counts.personalBests = try await uploadPersonalBests(memberId: memberId)
            counts.exerciseResets = try await uploadExerciseResets(memberId: memberId)
            return .completed(counts: counts)
        } catch {
            return .interrupted(counts: counts, error: error)
        }
    }

    private func uploadMembers(memberId: UUID) async throws -> Int {
        let pending = try localDataAccess.fetchDirtyMembers(memberId: memberId)
        guard !pending.isEmpty else { return 0 }

        var pushed = 0
        for member in pending {
            // Always filter by JWT member id — never mint a row if it is missing.
            let syncedAt = Date()
            let fields = SyncPayloadMapper.memberSettingsPatch(
                member,
                deviceId: credentials.deviceId,
                syncedAt: syncedAt
            )
            let updated = try await syncServiceAccess.patchMemberSettings(
                memberId: credentials.memberId,
                fields: fields
            )
            guard updated else {
                // Zero rows: broker has not established identity. Leave dirty; do not create.
                throw SyncError.memberIdentityNotEstablished
            }
            try localDataAccess.markMembersSynced([member], at: syncedAt)
            pushed += 1
        }
        return pushed
    }

    private func uploadSessions(memberId: UUID) async throws -> Int {
        let pending = try localDataAccess.fetchDirtySessions(memberId: memberId)
        return try await uploadInBatches(pending) { batch, syncedAt in
            let rows = batch.map {
                SyncPayloadMapper.sessionRow(
                    $0,
                    gymId: credentials.gymId,
                    deviceId: credentials.deviceId,
                    syncedAt: syncedAt
                )
            }
            try await syncServiceAccess.upsertSessions(rows)
            try localDataAccess.markSessionsSynced(batch, at: syncedAt)
        }
    }

    private func uploadExerciseEntries(memberId: UUID) async throws -> Int {
        let pending = try localDataAccess.fetchDirtyExerciseEntries(memberId: memberId)
        return try await uploadInBatches(pending) { batch, syncedAt in
            let rows = batch.map {
                SyncPayloadMapper.exerciseEntryRow(
                    $0,
                    gymId: credentials.gymId,
                    deviceId: credentials.deviceId,
                    syncedAt: syncedAt
                )
            }
            try await syncServiceAccess.upsertExerciseEntries(rows)
            try localDataAccess.markExerciseEntriesSynced(batch, at: syncedAt)
        }
    }

    private func uploadSets(memberId: UUID) async throws -> Int {
        let pending = try localDataAccess.fetchDirtySets(memberId: memberId)
        return try await uploadInBatches(pending) { batch, syncedAt in
            let rows = batch.map {
                SyncPayloadMapper.setRow(
                    $0,
                    gymId: credentials.gymId,
                    deviceId: credentials.deviceId,
                    syncedAt: syncedAt
                )
            }
            try await syncServiceAccess.upsertSets(rows)
            try localDataAccess.markSetsSynced(batch, at: syncedAt)
        }
    }

    private func uploadPersonalBests(memberId: UUID) async throws -> Int {
        let pending = try localDataAccess.fetchDirtyPersonalBests(memberId: memberId)
        return try await uploadInBatches(pending) { batch, syncedAt in
            let rows = batch.map {
                SyncPayloadMapper.personalBestRow(
                    $0,
                    gymId: credentials.gymId,
                    deviceId: credentials.deviceId,
                    syncedAt: syncedAt
                )
            }
            try await syncServiceAccess.upsertPersonalBests(rows)
            try localDataAccess.markPersonalBestsSynced(batch, at: syncedAt)
        }
    }

    private func uploadExerciseResets(memberId: UUID) async throws -> Int {
        let pending = try localDataAccess.fetchDirtyExerciseResets(memberId: memberId)
        return try await uploadInBatches(pending) { batch, syncedAt in
            let rows = batch.map {
                SyncPayloadMapper.exerciseResetRow(
                    $0,
                    gymId: credentials.gymId,
                    deviceId: credentials.deviceId,
                    syncedAt: syncedAt
                )
            }
            try await syncServiceAccess.upsertExerciseResets(rows)
            try localDataAccess.markExerciseResetsSynced(batch, at: syncedAt)
        }
    }

    private func uploadInBatches<T>(
        _ records: [T],
        uploadBatch: ([T], Date) async throws -> Void
    ) async throws -> Int {
        guard !records.isEmpty else { return 0 }

        var pushed = 0
        let chunks = records.chunked(into: batchSize)
        for chunk in chunks {
            let syncedAt = Date()
            try await uploadBatch(chunk, syncedAt)
            pushed += chunk.count
        }
        return pushed
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}
