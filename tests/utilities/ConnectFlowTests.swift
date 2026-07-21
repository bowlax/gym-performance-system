#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct ConnectAuthClientTests {
    @Test
    func authorizeURLIncludesReturnURLForAppCallback() throws {
        let deviceMemberId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let url = try OAuthConnectAuthClient.authorizeURL(
            brokerAuthorizeBaseURL: URL(string: "https://example.supabase.co/functions/v1/token-broker")!,
            deviceMemberId: deviceMemberId
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []

        #expect(queryItems.first(where: { $0.name == "oauth" })?.value == "authorize")
        #expect(
            queryItems.first(where: { $0.name == "deviceMemberId" })?.value
                == deviceMemberId.uuidString
        )
        #expect(queryItems.first(where: { $0.name == "surface" })?.value == "ios")
        #expect(
            queryItems.first(where: { $0.name == "returnUrl" })?.value
                == OAuthConnectAuthClient.callbackURL
        )
    }

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
            string: "gymperformance://connect?access_token=aaa.bbb.ccc&refresh_token=refresh.tok&expires_at=1735689600&token=aaa.bbb.ccc"
        )!
        let session = try OAuthConnectAuthClient.session(fromCallbackURL: url)
        #expect(session.token == "aaa.bbb.ccc")
        #expect(session.refreshToken == "refresh.tok")
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_735_689_600))
    }

    @Test
    func oauthCallbackParsesMangledDoubleQuestionMark() throws {
        // TeamUp can mangle the callback by using "?" instead of "&" for subsequent params.
        let url = URL(
            string: "gymperformance://connect?access_token=aaa.bbb.ccc?refresh_token=refresh.tok?expires_at=1735689600?token=aaa.bbb.ccc"
        )!
        let session = try OAuthConnectAuthClient.session(fromCallbackURL: url)
        #expect(session.token == "aaa.bbb.ccc")
        #expect(session.refreshToken == "refresh.tok")
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_735_689_600))
    }

    @Test
    func oauthCallbackReassemblesJWTSegmentsSplitByQuestionMark() throws {
        // Some redirects split JWT header/payload/signature on "?" instead of ".".
        let url = URL(
            string: "gymperformance://connect?access_token=aaa?bbb?ccc?refresh_token=refresh.tok?expires_at=1735689600"
        )!
        let session = try OAuthConnectAuthClient.session(fromCallbackURL: url)
        #expect(session.token == "aaa.bbb.ccc")
        #expect(session.refreshToken == "refresh.tok")
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

@Suite(.serialized)
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
            session: BrokerSession(token: "aaa.bbb.ccc", expiresAt: Date().addingTimeInterval(-60)),
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
                token: "aaa.bbb.ccc",
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
                token: "aaa.bbb.ccc",
                refreshToken: "refresh-secret",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            claims: claims
        )

        #expect(defaults.string(forKey: MemberConnectionStore.accessTokenKey) == nil)
        #expect(MemberConnectionStore.accessToken == "aaa.bbb.ccc")
        #expect(MemberConnectionStore.refreshToken == "refresh-secret")
        #expect(
            memory.string(forAccount: KeychainTokenStore.accessTokenAccount) == "aaa.bbb.ccc"
        )
        #expect(
            memory.string(forAccount: KeychainTokenStore.refreshTokenAccount) == "refresh-secret"
        )
    }

    @Test
    func stubSessionWithoutRefreshIsUsableWhenNotExpired() {
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
            session: BrokerSession(token: "aaa.bbb.ccc", refreshToken: nil, expiresAt: expires),
            claims: claims
        )

        #expect(MemberConnectionStore.hasUsableSession == true)
        #expect(MemberConnectionStore.brokerSessionIfUsable()?.token == "aaa.bbb.ccc")
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
                token: "aaa.bbb.ccc",
                refreshToken: nil,
                expiresAt: Date(timeIntervalSince1970: 1_000_000)
            ),
            claims: claims
        )

        let session = await MemberConnectionStore.ensureFreshSession()
        #expect(session == nil)
    }

    @Test
    func ensureFreshSessionRefreshesMalformedAccessToken() async {
        let defaults = UserDefaults(suiteName: "MemberConnectionStoreTests.malformed.\(UUID().uuidString)")!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        let previousSession = GoTrueTokenRefresher.urlSession
        setenv("GYMPERF_SUPABASE_URL", "https://example.supabase.co", 1)
        setenv("GYMPERF_SUPABASE_PUBLISHABLE_KEY", "pk_test", 1)
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
            GoTrueTokenRefresher.urlSession = previousSession
            unsetenv("GYMPERF_SUPABASE_URL")
            unsetenv("GYMPERF_SUPABASE_PUBLISHABLE_KEY")
        }

        let refreshedJWT = "aaa.bbb.ccc"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGoTrueRefreshURLProtocol.self]
        MockGoTrueRefreshURLProtocol.responseHandler = { request in
            #expect(request.url?.absoluteString.contains("/auth/v1/token") == true)
            let body = """
            {"access_token":"\(refreshedJWT)","refresh_token":"rotated-refresh","expires_at":9999999999}
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        GoTrueTokenRefresher.urlSession = URLSession(configuration: config)

        let claims = JWTClaimsDecoder.Claims(memberId: UUID(), gymId: UUID())
        MemberConnectionStore.save(
            session: BrokerSession(
                token: "aaa.bbb.ccc",
                refreshToken: "stale-refresh",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            claims: claims
        )
        memory.setString("not-a-jwt", forAccount: KeychainTokenStore.accessTokenAccount)

        let session = await MemberConnectionStore.ensureFreshSession()
        #expect(session?.token == refreshedJWT)
        #expect(MemberConnectionStore.accessToken == refreshedJWT)
        #expect(MemberConnectionStore.refreshToken == "rotated-refresh")
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

private final class MockGoTrueRefreshURLProtocol: URLProtocol {
    static var responseHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.responseHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
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
