import Foundation
import SwiftData

/// Result of discard-cloud-wins (#33): clear anonymous local history, then pull.
struct DiscardCloudWinsResult: Equatable, Sendable {
    /// Local anonymous training rows were removed.
    let cleared: Bool
    let pull: SyncPullResult?
    let completed: Bool
    let errorMessage: String?

    /// Clear finished but pull did not — device is empty; cloud still has the account history.
    var clearedButPullIncomplete: Bool {
        cleared && !(pull?.completed ?? false)
    }

    static func failedBeforeClear(error: Error) -> DiscardCloudWinsResult {
        DiscardCloudWinsResult(
            cleared: false,
            pull: nil,
            completed: false,
            errorMessage: error.localizedDescription
        )
    }

    static func clearedThenPull(_ pull: SyncPullResult) -> DiscardCloudWinsResult {
        DiscardCloudWinsResult(
            cleared: true,
            pull: pull,
            completed: pull.completed,
            errorMessage: pull.completed ? nil : pull.errorMessage
        )
    }
}

/// Anonymous-local-then-adopt resolution (#33): **discard-cloud-wins**.
///
/// ## Why not just merge the two histories?
/// LWW only resolves *the same record* edited on two devices. It has no concept of
/// "these two sessions are really the same session". Matching by similarity would be
/// a heuristic that either merges distinct real sessions or leaves everything
/// duplicated. So we never re-parent or de-duplicate: clear local anonymous data,
/// then pull the account's cloud history.
///
/// ## What is cleared
/// Training history for the **anonymous local member id**: sessions, exercise
/// entries, sets, personal bests (including manuals), exercise resets. Hard-deleted
/// so nothing is left to push under the abandoned id.
///
/// ## What survives
/// - **Device UUID** (`SyncDeviceIdentity`) — install identity for `source_device_id`, not training data.
/// - **Exercise catalog** — shared seed, not member history.
/// - **Anonymous `UserIdentityModel` / staleness** — not migrated onto the adopted
///   member. After adopt, preferences come from the cloud member row (or defaults).
///   Copying local staleness would be a soft merge of two identities' settings.
enum DiscardCloudWins {
    /// Hard-delete all training rows owned by `anonymousMemberId`.
    @MainActor
    static func clearAnonymousLocalHistory(
        anonymousMemberId: UUID,
        in context: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws {
        let sessions = try performanceDataAccess.fetchSessions(memberId: anonymousMemberId)
        for session in sessions {
            let entries = try performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
            for entry in entries {
                let sets = try performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                for set in sets {
                    context.delete(set)
                }
                context.delete(entry)
            }
            context.delete(session)
        }

        let pbDescriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == anonymousMemberId }
        )
        for pb in try context.fetch(pbDescriptor) {
            context.delete(pb)
        }

        let resetDescriptor = FetchDescriptor<ExerciseResetModel>(
            predicate: #Predicate { $0.memberId == anonymousMemberId }
        )
        for reset in try context.fetch(resetDescriptor) {
            context.delete(reset)
        }

        let identityDescriptor = FetchDescriptor<UserIdentityModel>(
            predicate: #Predicate { $0.id == anonymousMemberId }
        )
        for identity in try context.fetch(identityDescriptor) {
            context.delete(identity)
        }

        try context.save()
    }
}
