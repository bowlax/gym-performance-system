import Foundation
import Observation
import SwiftData

/// Triggers and UI status for the Sync Manager (#32). Mechanism stays in `SyncManager`.
///
/// **Fence:** inherits `ConnectFeatureAvailability` — Release never connects, so
/// sync never has a usable session. Anonymous (not connected) also never syncs.
@MainActor
@Observable
final class SyncCoordinator {
    /// Brief floor so manual "Sync now" always shows visible consequence.
    static let manualMinimumVisibleDuration: TimeInterval = 0.6

    private(set) var isSyncing = false
    /// Set only when the member asked (manual Sync now) and the cycle failed.
    private(set) var lastManualError: String?

    private let modelContext: ModelContext
    private var inFlightTask: Task<SyncCycleResult?, Never>?
    private var pendingAfterCurrent = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Triggers

    /// After a session is saved — full cycle, no throttle.
    func syncAfterSessionSaved() {
        Task { _ = await runCycle(trigger: .sessionSaved) }
    }

    /// App became active — full cycle only if last success is older than 6 hours.
    func syncOnForeground() {
        Task { _ = await runCycle(trigger: .foreground) }
    }

    /// Settings "Sync now" — bypasses throttle; surfaces failure to the asker.
    @discardableResult
    func syncNow() async -> SyncCycleResult? {
        lastManualError = nil
        return await runCycle(trigger: .manual)
    }

    /// First-connect upload succeeded (#31) — treat as a successful sync for display.
    func recordFirstConnectUploadSuccess(memberId: UUID, at date: Date = Date()) {
        SyncStatusStore.recordSuccess(memberId: memberId, at: date)
    }

    func clearManualError() {
        lastManualError = nil
    }

    // MARK: - Settings reads

    var connectedMemberId: UUID? {
        MemberConnectionStore.connectedMemberId
    }

    var lastSuccessfulCycleAt: Date? {
        guard let memberId = connectedMemberId else { return nil }
        return SyncStatusStore.lastSuccessfulCycleAt(memberId: memberId)
    }

    var unrecoveredFailureMessage: String? {
        guard let memberId = connectedMemberId else { return nil }
        return SyncStatusStore.unrecoveredFailureMessage(memberId: memberId)
    }

    // MARK: - Cycle

    private enum Trigger {
        case sessionSaved
        case foreground
        case manual
    }

    private func runCycle(trigger: Trigger) async -> SyncCycleResult? {
        guard ConnectFeatureAvailability.isAvailable else { return nil }
        guard MemberConnectionStore.hasUsableSession,
              let session = MemberConnectionStore.brokerSessionIfUsable(),
              let memberId = MemberConnectionStore.connectedMemberId else {
            return nil
        }

        if trigger == .foreground,
           !SyncStatusStore.shouldRunForegroundSync(memberId: memberId) {
            return nil
        }

        if let existing = inFlightTask {
            if trigger == .manual {
                _ = await existing.value
                // Fresh cycle so "Sync now" reflects post-ask state.
                return await startCycle(session: session, memberId: memberId, trigger: trigger)
            }
            if trigger == .sessionSaved {
                pendingAfterCurrent = true
            }
            return await existing.value
        }

        return await startCycle(session: session, memberId: memberId, trigger: trigger)
    }

    private func startCycle(
        session: BrokerSession,
        memberId: UUID,
        trigger: Trigger
    ) async -> SyncCycleResult? {
        let task = Task<SyncCycleResult?, Never> { @MainActor in
            self.isSyncing = true
            defer {
                self.isSyncing = false
                self.inFlightTask = nil
            }

            let started = Date()
            let result: SyncCycleResult
            do {
                let manager = try SyncManager.makeFromCloudConfig(modelContext: self.modelContext)
                result = await manager.runFullSyncCycle(brokerSession: session)
            } catch {
                result = SyncCycleResult(
                    pull: .interrupted(
                        mergeCounts: SyncMergeCounts(),
                        highWaterSyncedAt: nil,
                        error: error
                    ),
                    push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
                )
            }

            if trigger == .manual {
                let elapsed = Date().timeIntervalSince(started)
                let remaining = Self.manualMinimumVisibleDuration - elapsed
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }

            if result.completed {
                SyncStatusStore.recordSuccess(memberId: memberId)
                if trigger == .manual {
                    self.lastManualError = nil
                }
            } else {
                let message = result.errorMessage ?? "Sync failed"
                SyncStatusStore.recordFailure(memberId: memberId, message: message)
                if trigger == .manual {
                    self.lastManualError = message
                }
                // Automatic triggers: silent — Settings shows unrecovered failure only.
            }

            return result
        }

        inFlightTask = task
        let result = await task.value

        if pendingAfterCurrent {
            pendingAfterCurrent = false
            return await runCycle(trigger: .sessionSaved)
        }

        return result
    }
}
