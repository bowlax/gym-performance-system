#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct ConnectAuthClientTests {
    @Test
    func oauthCallbackParsesTokenAndExpiry() throws {
        let url = URL(string: "gymperformance://connect?token=abc.def.ghi&expires_at=1735689600")!
        let session = try OAuthConnectAuthClient.session(fromCallbackURL: url)
        #expect(session.token == "abc.def.ghi")
        #expect(session.refreshToken == nil)
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_735_689_600))
    }

    @Test
    func oauthCallbackParsesAuthSessionPair() throws {
        let url = URL(
            string: "gymperformance://connect?access_token=access.jwt&refresh_token=refresh.tok&expires_at=1735689600&token=access.jwt"
        )!
        let session = try OAuthConnectAuthClient.session(fromCallbackURL: url)
        #expect(session.token == "access.jwt")
        #expect(session.refreshToken == "refresh.tok")
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_735_689_600))
    }

    @Test
    func oauthCallbackRejectsMissingToken() {
        let url = URL(string: "gymperformance://connect?error=access_denied")!
        do {
            _ = try OAuthConnectAuthClient.session(fromCallbackURL: url)
            Issue.record("Expected missing token to throw")
        } catch is SyncError {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite
struct MemberConnectionStoreTests {
    @Test
    func dontAskAgainAndSessionExpiryAreDistinct() {
        let defaults = UserDefaults(suiteName: "MemberConnectionStoreTests.\(UUID().uuidString)")!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
        }

        #expect(MemberConnectionStore.isConnected == false)
        #expect(MemberConnectionStore.sessionNeedsReauth == false)

        MemberConnectionStore.dontAskConnectAgain = true
        #expect(MemberConnectionStore.dontAskConnectAgain == true)
        #expect(MemberConnectionStore.isConnected == false)

        let claims = JWTClaimsDecoder.Claims(
            memberId: UUID(),
            gymId: UUID()
        )
        MemberConnectionStore.save(
            session: BrokerSession(token: "tok", expiresAt: Date().addingTimeInterval(-60)),
            claims: claims
        )
        #expect(MemberConnectionStore.isConnected == true)
        #expect(MemberConnectionStore.sessionNeedsReauth == true)

        MemberConnectionStore.markSessionExpired()
        #expect(MemberConnectionStore.isConnected == true)
        #expect(MemberConnectionStore.accessToken == nil)
        #expect(MemberConnectionStore.refreshToken == nil)
        #expect(MemberConnectionStore.sessionNeedsReauth == true)
    }

    @Test
    func refreshTokenDefersReauthUntilRefreshFails() {
        let defaults = UserDefaults(suiteName: "MemberConnectionStoreTests.refresh.\(UUID().uuidString)")!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
        }

        let claims = JWTClaimsDecoder.Claims(memberId: UUID(), gymId: UUID())
        MemberConnectionStore.save(
            session: BrokerSession(
                token: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(-60)
            ),
            claims: claims
        )
        #expect(MemberConnectionStore.sessionNeedsReauth == false)
        #expect(MemberConnectionStore.hasUsableSession == true)
    }

    @Test
    func tokensLiveInKeychainNotUserDefaults() {
        let defaults = UserDefaults(suiteName: "MemberConnectionStoreTests.keychain.\(UUID().uuidString)")!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
        }

        let claims = JWTClaimsDecoder.Claims(memberId: UUID(), gymId: UUID())
        MemberConnectionStore.save(
            session: BrokerSession(
                token: "access-secret",
                refreshToken: "refresh-secret",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            claims: claims
        )

        #expect(defaults.string(forKey: MemberConnectionStore.accessTokenKey) == nil)
        #expect(MemberConnectionStore.accessToken == "access-secret")
        #expect(MemberConnectionStore.refreshToken == "refresh-secret")
        #expect(
            memory.string(forAccount: KeychainTokenStore.accessTokenAccount) == "access-secret"
        )
        #expect(
            memory.string(forAccount: KeychainTokenStore.refreshTokenAccount) == "refresh-secret"
        )
    }

    @Test
    func ensureFreshSessionNoOpWithoutRefreshToken() async {
        let defaults = UserDefaults(suiteName: "MemberConnectionStoreTests.stub.\(UUID().uuidString)")!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        let previousNow = GoTrueTokenRefresher.now
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        GoTrueTokenRefresher.now = { Date(timeIntervalSince1970: 1_000_000) }
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
            GoTrueTokenRefresher.now = previousNow
        }

        let claims = JWTClaimsDecoder.Claims(memberId: UUID(), gymId: UUID())
        let expires = Date(timeIntervalSince1970: 1_000_000 + 3_600)
        MemberConnectionStore.save(
            session: BrokerSession(token: "stub-hs256", refreshToken: nil, expiresAt: expires),
            claims: claims
        )

        let session = await MemberConnectionStore.ensureFreshSession()
        #expect(session?.token == "stub-hs256")
        #expect(session?.refreshToken == nil)
    }

    @Test
    func ensureFreshSessionNilWhenStubExpired() async {
        let defaults = UserDefaults(suiteName: "MemberConnectionStoreTests.stubExpired.\(UUID().uuidString)")!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        let previousNow = GoTrueTokenRefresher.now
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        GoTrueTokenRefresher.now = { Date(timeIntervalSince1970: 2_000_000) }
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
            GoTrueTokenRefresher.now = previousNow
        }

        let claims = JWTClaimsDecoder.Claims(memberId: UUID(), gymId: UUID())
        MemberConnectionStore.save(
            session: BrokerSession(
                token: "stub-hs256",
                refreshToken: nil,
                expiresAt: Date(timeIntervalSince1970: 1_000_000)
            ),
            claims: claims
        )

        let session = await MemberConnectionStore.ensureFreshSession()
        #expect(session == nil)
    }

    @Test
    func migratesLegacyUserDefaultsAccessTokenToKeychain() {
        let defaults = UserDefaults(suiteName: "MemberConnectionStoreTests.legacy.\(UUID().uuidString)")!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
        }

        defaults.set("legacy-access", forKey: MemberConnectionStore.accessTokenKey)
        #expect(MemberConnectionStore.accessToken == "legacy-access")
        #expect(defaults.string(forKey: MemberConnectionStore.accessTokenKey) == nil)
        #expect(
            memory.string(forAccount: KeychainTokenStore.accessTokenAccount) == "legacy-access"
        )
    }
}

@Suite
struct GoTrueTokenRefresherTests {
    @Test
    func needsRefreshRespectsSkewWindow() {
        let previousSkew = GoTrueTokenRefresher.skew
        GoTrueTokenRefresher.skew = 60
        defer { GoTrueTokenRefresher.skew = previousSkew }

        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(
            GoTrueTokenRefresher.needsRefresh(
                accessToken: "a",
                expiresAt: now.addingTimeInterval(30),
                hasRefreshToken: true,
                now: now
            ) == true
        )
        #expect(
            GoTrueTokenRefresher.needsRefresh(
                accessToken: "a",
                expiresAt: now.addingTimeInterval(120),
                hasRefreshToken: true,
                now: now
            ) == false
        )
        #expect(
            GoTrueTokenRefresher.needsRefresh(
                accessToken: "a",
                expiresAt: now.addingTimeInterval(-10),
                hasRefreshToken: false,
                now: now
            ) == false
        )
    }
}
#endif
