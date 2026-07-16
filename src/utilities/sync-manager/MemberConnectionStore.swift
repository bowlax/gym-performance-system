import Foundation

/// Persisted connection state for the member surface (#31).
///
/// Identity UUID remains in `AccessControl`. This store tracks whether the
/// member has completed TeamUp connect and holds the broker JWT for sync.
///
/// "Don't ask again" is local-only (anonymous members have nowhere else to
/// put it). It will not survive a reinstall — correct, because a reinstall
/// is also when cloud data might be waiting.
enum MemberConnectionStore {
    static let isConnectedKey = "memberConnection.isConnected"
    static let accessTokenKey = "memberConnection.accessToken"
    static let expiresAtKey = "memberConnection.expiresAt"
    static let connectedMemberIdKey = "memberConnection.memberId"
    static let connectedGymIdKey = "memberConnection.gymId"
    /// Local opt-out for the launch connect prompt (#31).
    static let dontAskConnectAgainKey = "memberConnection.dontAskConnectAgain"

    static var userDefaults: UserDefaults = .standard

    static var isConnected: Bool {
        get { userDefaults.bool(forKey: isConnectedKey) }
        set { userDefaults.set(newValue, forKey: isConnectedKey) }
    }

    static var dontAskConnectAgain: Bool {
        get { userDefaults.bool(forKey: dontAskConnectAgainKey) }
        set { userDefaults.set(newValue, forKey: dontAskConnectAgainKey) }
    }

    static var accessToken: String? {
        get { userDefaults.string(forKey: accessTokenKey) }
        set { userDefaults.set(newValue, forKey: accessTokenKey) }
    }

    static var connectedMemberId: UUID? {
        get {
            guard let raw = userDefaults.string(forKey: connectedMemberIdKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set { userDefaults.set(newValue?.uuidString, forKey: connectedMemberIdKey) }
    }

    static var expiresAt: Date? {
        get {
            let interval = userDefaults.double(forKey: expiresAtKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let newValue {
                userDefaults.set(newValue.timeIntervalSince1970, forKey: expiresAtKey)
            } else {
                userDefaults.removeObject(forKey: expiresAtKey)
            }
        }
    }

    /// Connected but the stored session is missing or past expiry.
    /// Distinct from never-connected — copy must not say "connect to sync".
    static var sessionNeedsReauth: Bool {
        guard isConnected else { return false }
        guard let token = accessToken, !token.isEmpty else { return true }
        if let expiresAt, expiresAt <= Date() { return true }
        return false
    }

    static var hasUsableSession: Bool {
        isConnected && !sessionNeedsReauth
    }

    static func save(session: BrokerSession, claims: JWTClaimsDecoder.Claims) {
        accessToken = session.token
        expiresAt = session.expiresAt
        connectedMemberId = claims.memberId
        userDefaults.set(claims.gymId.uuidString, forKey: connectedGymIdKey)
        isConnected = true
        dontAskConnectAgain = true
    }

    static func brokerSessionIfUsable() -> BrokerSession? {
        guard hasUsableSession, let token = accessToken else { return nil }
        return BrokerSession(token: token, expiresAt: expiresAt)
    }

    /// Clears the JWT but keeps `isConnected` so we can show the *session expired*
    /// prompt rather than the never-connected prompt.
    static func markSessionExpired() {
        accessToken = nil
        expiresAt = nil
    }
}
