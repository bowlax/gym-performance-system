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

    static func fromBrokerSession(_ session: BrokerSession) throws -> SyncCredentials {
        let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: session.token)
        guard let publishableKey = GymPerfCloudConfig.publishableKey,
              let supabaseURL = GymPerfCloudConfig.supabaseURL else {
            throw SyncError.cloudNotConfigured
        }
        return SyncCredentials(
            supabaseURL: supabaseURL,
            publishableKey: publishableKey,
            accessToken: session.token,
            memberId: claims.memberId,
            gymId: claims.gymId,
            deviceId: SyncDeviceIdentity.persistedDeviceId()
        )
    }
}
