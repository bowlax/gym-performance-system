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
        let previous = MemberConnectionStore.userDefaults
        MemberConnectionStore.userDefaults = defaults
        defer {
            MemberConnectionStore.userDefaults = previous
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
        #expect(MemberConnectionStore.sessionNeedsReauth == true)
    }
}
#endif
