import Foundation

/// RLS-scoped cloud session used for sync uploads.
struct SyncCredentials: Equatable, Sendable {
    let supabaseURL: URL
    let publishableKey: String
    let accessToken: String
    let memberId: UUID
    let gymId: UUID
    let deviceId: UUID

    var restAPIBaseURL: URL {
        supabaseURL.appendingPathComponent("rest/v1")
    }
}
