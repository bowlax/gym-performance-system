import Foundation

/// Persisted connection state for the member surface (#31 / #17).
///
/// Identity UUID remains in `AccessControl`. This store tracks whether the
/// member has completed TeamUp connect and holds the broker session for sync.
///
/// **Secrets:** access + refresh tokens live in the Keychain (`KeychainTokenStore`).
/// Non-secrets (`expiresAt`, member/gym ids, flags) stay in UserDefaults.
///
/// Legacy: pre-Keychain builds stored the access token in UserDefaults under
/// `accessTokenKey`. On read, that value is migrated into Keychain once and
/// removed from UserDefaults. Connect is still fenced, so no production
/// sessions need migrating — this keeps absent/legacy state graceful.
///
/// "Don't ask again" is local-only (anonymous members have nowhere else to
/// put it). It will not survive a reinstall — correct, because a reinstall
/// is also when cloud data might be waiting.
enum MemberConnectionStore {
    static let isConnectedKey = "memberConnection.isConnected"
    /// Legacy UserDefaults key — migrated to Keychain on access, then cleared.
    static let accessTokenKey = "memberConnection.accessToken"
    static let expiresAtKey = "memberConnection.expiresAt"
    static let connectedMemberIdKey = "memberConnection.memberId"
    static let connectedGymIdKey = "memberConnection.gymId"
    /// Local opt-out for the launch connect prompt (#31).
    static let dontAskConnectAgainKey = "memberConnection.dontAskConnectAgain"
    /// One-shot: skip the *next* never-connected launch evaluation after
    /// onboarding already offered connect. Cleared when consumed — not a
    /// permanent opt-out (unlike `dontAskConnectAgain`).
    static let offeredConnectDuringOnboardingKey =
        "memberConnection.offeredConnectDuringOnboarding"
    /// Set once on first successful connect; never cleared by disconnect.
    /// Cheap guard signal for "this install has been through TeamUp before."
    static let hasEverConnectedKey = "memberConnection.hasEverConnected"
    /// Last member id that successfully connected on this install.
    /// Survives disconnect so reconnect can refuse a *different* TeamUp account.
    static let lastConnectedMemberIdKey = "memberConnection.lastConnectedMemberId"

    static var userDefaults: UserDefaults = .standard

    /// Single-flight gate so concurrent sync triggers share one refresh.
    private static let refreshGate = SessionRefreshGate()

    static var isConnected: Bool {
        get { userDefaults.bool(forKey: isConnectedKey) }
        set { userDefaults.set(newValue, forKey: isConnectedKey) }
    }

    static var dontAskConnectAgain: Bool {
        get { userDefaults.bool(forKey: dontAskConnectAgainKey) }
        set { userDefaults.set(newValue, forKey: dontAskConnectAgainKey) }
    }

    /// When true, the next `ConnectLaunchPrompts` evaluation should skip the
    /// never-connected sheet once (immediate post-onboarding re-ask), then
    /// clear this flag so later launches behave like a normal “Not now”.
    static var offeredConnectDuringOnboarding: Bool {
        get { userDefaults.bool(forKey: offeredConnectDuringOnboardingKey) }
        set { userDefaults.set(newValue, forKey: offeredConnectDuringOnboardingKey) }
    }

    /// Consume the one-shot onboarding skip. Returns whether this evaluation
    /// should suppress the never-connected prompt.
    @discardableResult
    static func consumeOnboardingConnectOfferSkip() -> Bool {
        guard offeredConnectDuringOnboarding else { return false }
        offeredConnectDuringOnboarding = false
        return true
    }

    /// True after at least one successful `save` on this install (or legacy migrate).
    /// Disconnect does **not** clear this.
    static var hasEverConnected: Bool {
        get { userDefaults.bool(forKey: hasEverConnectedKey) }
        set { userDefaults.set(newValue, forKey: hasEverConnectedKey) }
    }

    /// Member id from the last successful connect. Survives disconnect.
    static var lastConnectedMemberId: UUID? {
        get {
            guard let raw = userDefaults.string(forKey: lastConnectedMemberIdKey) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set { userDefaults.set(newValue?.uuidString, forKey: lastConnectedMemberIdKey) }
    }

    /// Migrate pre-flag installs that are already connected.
    static func migrateEverConnectedFlagsIfNeeded() {
        guard !hasEverConnected, isConnected, let id = connectedMemberId else { return }
        hasEverConnected = true
        if lastConnectedMemberId == nil {
            lastConnectedMemberId = id
        }
    }

    static var accessToken: String? {
        get {
            if let keychain = KeychainTokenStore.string(
                forAccount: KeychainTokenStore.accessTokenAccount
            ), !keychain.isEmpty {
                return keychain
            }
            // Legacy migration: UserDefaults → Keychain.
            if let legacy = userDefaults.string(forKey: accessTokenKey), !legacy.isEmpty {
                KeychainTokenStore.setString(
                    legacy,
                    forAccount: KeychainTokenStore.accessTokenAccount
                )
                userDefaults.removeObject(forKey: accessTokenKey)
                return legacy
            }
            return nil
        }
        set {
            KeychainTokenStore.setString(
                newValue,
                forAccount: KeychainTokenStore.accessTokenAccount
            )
            userDefaults.removeObject(forKey: accessTokenKey)
        }
    }

    static var refreshToken: String? {
        get {
            KeychainTokenStore.string(forAccount: KeychainTokenStore.refreshTokenAccount)
        }
        set {
            KeychainTokenStore.setString(
                newValue,
                forAccount: KeychainTokenStore.refreshTokenAccount
            )
        }
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

    /// Connected but the stored session cannot be used without reconnecting.
    ///
    /// When a refresh token is present, expiry of the access token alone does
    /// **not** mean reauth — `ensureFreshSession` can rotate silently. Reauth
    /// is required when there is no refresh token and the access JWT is missing
    /// or past expiry (stub / Bearer-until-expiry behaviour).
    static var sessionNeedsReauth: Bool {
        guard isConnected else { return false }
        if let refresh = refreshToken, !refresh.isEmpty {
            return false
        }
        guard let token = accessToken, !token.isEmpty else { return true }
        if let expiresAt, expiresAt <= GoTrueTokenRefresher.now() { return true }
        return false
    }

    static var hasUsableSession: Bool {
        isConnected && !sessionNeedsReauth
    }

    static func save(session: BrokerSession, claims: JWTClaimsDecoder.Claims) {
        accessToken = JWTClaimsDecoder.normalizeToken(session.token)
        refreshToken = session.refreshToken
        expiresAt = session.expiresAt
        connectedMemberId = claims.memberId
        userDefaults.set(claims.gymId.uuidString, forKey: connectedGymIdKey)
        isConnected = true
        dontAskConnectAgain = true
        hasEverConnected = true
        lastConnectedMemberId = claims.memberId
    }

    /// Synchronous snapshot for callers that cannot await. Prefer
    /// `ensureFreshSession()` before network work so Auth-path tokens refresh.
    static func brokerSessionIfUsable() -> BrokerSession? {
        guard hasUsableSession, let token = accessToken else { return nil }
        return BrokerSession(
            token: token,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    /// Returns a usable session, refreshing via GoTrue when a refresh token is
    /// present and the access token is missing or within the skew window.
    ///
    /// Stub path (`refreshToken == nil`): no-op beyond today's expiry check.
    /// Concurrent callers share one in-flight refresh (rotation-safe).
    static func ensureFreshSession() async -> BrokerSession? {
        await refreshGate.ensureFreshSession()
    }

    /// Clears secrets but keeps `isConnected` so we can show the *session expired*
    /// prompt rather than the never-connected prompt.
    static func markSessionExpired() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        KeychainTokenStore.clearSessionTokens()
        userDefaults.removeObject(forKey: accessTokenKey)
    }

    /// Stop syncing on this device. Does **not** delete cloud or local training data.
    ///
    /// Clears the broker session (same secrets as `markSessionExpired`) and sets
    /// `isConnected = false` so Settings shows Connect again and launch can offer
    /// reconnect (`dontAskConnectAgain` reset to false). Leaves
    /// `AccessControl.persistedMemberId`, SwiftData rows, and `MemberState` alone —
    /// local history stays tagged with the adopted canonical id.
    ///
    /// Device-swap after disconnect (reconnecting a DIFFERENT TeamUp account on a
    /// device that previously connected as someone else) is a known unhandled case.
    /// Accepted because Wolf's member population does not share devices. If that
    /// assumption ever changes, the identity model needs the fuller fix (stable
    /// device id separate from adopted member id) before this scenario is safe.
    /// Until then, `ConnectBranchLogic.shouldBlockDifferentAccount` refuses that
    /// path with a visible message instead of discard/retag.
    static func disconnect() {
        migrateEverConnectedFlagsIfNeeded()
        if let id = connectedMemberId {
            lastConnectedMemberId = id
            hasEverConnected = true
        }
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        KeychainTokenStore.clearSessionTokens()
        userDefaults.removeObject(forKey: accessTokenKey)
        connectedMemberId = nil
        userDefaults.removeObject(forKey: connectedGymIdKey)
        isConnected = false
        dontAskConnectAgain = false
        // Intentionally keep hasEverConnected + lastConnectedMemberId.
    }
}

// MARK: - Single-flight refresh

private actor SessionRefreshGate {
    private var inFlight: Task<BrokerSession?, Never>?

    func ensureFreshSession() async -> BrokerSession? {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task<BrokerSession?, Never> { @MainActor in
            await Self.performEnsureFreshSession()
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    @MainActor
    private static func performEnsureFreshSession() async -> BrokerSession? {
        guard MemberConnectionStore.isConnected else { return nil }

        let access = MemberConnectionStore.accessToken.map(JWTClaimsDecoder.normalizeToken)
        let refresh = MemberConnectionStore.refreshToken
        let expiresAt = MemberConnectionStore.expiresAt

        // Stub / HS256: no refresh token — same as Bearer-until-expiry.
        guard let refresh, !refresh.isEmpty else {
            guard let access, !access.isEmpty,
                  JWTClaimsDecoder.isWellFormedJWT(access) else {
                return nil
            }
            if let expiresAt, expiresAt <= GoTrueTokenRefresher.now() {
                return nil
            }
            return BrokerSession(token: access, refreshToken: nil, expiresAt: expiresAt)
        }

        let accessMalformed = access.map { !JWTClaimsDecoder.isWellFormedJWT($0) } ?? true
        let needsRefresh = accessMalformed || GoTrueTokenRefresher.needsRefresh(
            accessToken: access,
            expiresAt: expiresAt,
            hasRefreshToken: true
        )

        if !needsRefresh, let access, !access.isEmpty {
            return BrokerSession(
                token: access,
                refreshToken: refresh,
                expiresAt: expiresAt
            )
        }

        guard let supabaseURL = GymPerfCloudConfig.supabaseURL,
              let publishableKey = GymPerfCloudConfig.publishableKey else {
            MemberConnectionStore.markSessionExpired()
            return nil
        }

        do {
            let refreshed = try await GoTrueTokenRefresher.refresh(
                refreshToken: refresh,
                supabaseURL: supabaseURL,
                publishableKey: publishableKey
            )
            // CRITICAL: persist rotated refresh_token — old one is invalidated.
            MemberConnectionStore.accessToken = refreshed.accessToken
            MemberConnectionStore.refreshToken = refreshed.refreshToken
            MemberConnectionStore.expiresAt = refreshed.expiresAt
            return BrokerSession(
                token: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: refreshed.expiresAt
            )
        } catch {
            MemberConnectionStore.markSessionExpired()
            return nil
        }
    }
}
