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
        return try await uploadSetRecords(pending)
    }

    private func uploadPersonalBests(memberId: UUID) async throws -> Int {
        let pending = try localDataAccess.fetchDirtyPersonalBests(memberId: memberId)
        try await uploadSetsReferencedBy(pending)
        return try await uploadInBatches(pending) { batch, syncedAt in
            let rows = batch.map { personalBestRowForUpload($0, syncedAt: syncedAt) }
            try await syncServiceAccess.upsertPersonalBests(rows)
            try localDataAccess.markPersonalBestsSynced(batch, at: syncedAt)
        }
    }

    /// PB rows may reference sets that are locally "clean" (syncedAt set) but absent
    /// from cloud — e.g. after identity heal when only PBs were retagged dirty.
    private func uploadSetsReferencedBy(_ personalBests: [PersonalBestModel]) async throws {
        let referencedIds = Set(personalBests.compactMap(\.setId))
        guard !referencedIds.isEmpty else { return }

        var sets: [ModelSet] = []
        for id in referencedIds {
            if let set = try localDataAccess.set(id: id) {
                sets.append(set)
            }
        }
        try await uploadDependencyChainForSets(sets)
    }

    /// Upserts sessions, entries, and sets for PB FK targets even when locally clean.
    private func uploadDependencyChainForSets(_ sets: [ModelSet]) async throws {
        guard !sets.isEmpty else { return }

        var sessionsById: [UUID: SessionModel] = [:]
        var entriesById: [UUID: ExerciseEntryModel] = [:]
        for set in sets {
            guard let entry = try localDataAccess.exerciseEntry(id: set.exerciseEntryId),
                  let session = try localDataAccess.session(id: entry.sessionId) else {
                continue
            }
            entriesById[entry.id] = entry
            sessionsById[session.id] = session
        }

        if !sessionsById.isEmpty {
            _ = try await uploadInBatches(Array(sessionsById.values)) { batch, syncedAt in
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

        if !entriesById.isEmpty {
            _ = try await uploadInBatches(Array(entriesById.values)) { batch, syncedAt in
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

        _ = try await uploadSetRecords(sets)
    }

    private func uploadSetRecords(_ sets: [ModelSet]) async throws -> Int {
        try await uploadInBatches(sets) { batch, syncedAt in
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

    private func personalBestRowForUpload(
        _ pb: PersonalBestModel,
        syncedAt: Date
    ) -> [String: Any] {
        var row = SyncPayloadMapper.personalBestRow(
            pb,
            gymId: credentials.gymId,
            deviceId: credentials.deviceId,
            syncedAt: syncedAt
        )
        if let setId = pb.setId, (try? localDataAccess.set(id: setId)) == nil {
            row["set_id"] = NSNull()
        }
        return row
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
