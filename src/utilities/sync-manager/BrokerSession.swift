import Foundation

/// Session minted by the token broker after a successful connect (#17 / #31).
///
/// - Stub path: `token` only (HS256); `refreshToken` is nil — no silent refresh.
/// - Auth path: ES256 `token` (= access_token) plus `refreshToken` for GoTrue refresh.
struct BrokerSession: Equatable, Sendable {
    /// Access JWT used as `Authorization: Bearer` for PostgREST / Edge Functions.
    let token: String
    /// GoTrue refresh token. Absent on the stub HS256 path.
    let refreshToken: String?
    let expiresAt: Date?

    init(token: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.token = token
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}
