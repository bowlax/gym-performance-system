import Foundation
import Testing
@testable import GymPerformance

/// Live GoTrue refresh via the real iOS `GoTrueTokenRefresher` (#17).
///
/// `scripts/prove-ios-refresh-live.mjs` writes `LiveRefreshProofFixture.generated.swift`
/// with a real refresh_token, then runs this test via xcodebuild. Ordinary unit-test
/// runs leave the fixture empty and this test is disabled.
struct GoTrueTokenRefresherLiveTests {
    /// GoTrue keeps a used refresh_token redeemable for the same child tokens
    /// during the reuse interval (concurrent refresh). Parent invalidation sticks
    /// only after the child is used and that interval elapses.
    private static let reuseInterval: Duration = .seconds(20)

    /// Skipped unless `prove-ios-refresh-live.mjs` wrote a live fixture.
    @Test(.enabled(if: LiveRefreshProofFixture.isConfigured))
    func liveRefreshRotatesAndKeepsTopLevelClaims() async throws {
        guard let supabaseURL = URL(string: LiveRefreshProofFixture.supabaseURL) else {
            Issue.record("Invalid supabaseURL in LiveRefreshProofFixture")
            return
        }

        let oldRefresh = LiveRefreshProofFixture.refreshToken
        let refreshed = try await GoTrueTokenRefresher.refresh(
            refreshToken: oldRefresh,
            supabaseURL: supabaseURL,
            publishableKey: LiveRefreshProofFixture.publishableKey
        )

        #expect(refreshed.accessToken.isEmpty == false)
        #expect(refreshed.refreshToken.isEmpty == false)
        #expect(
            refreshed.refreshToken != oldRefresh,
            "GoTrue must rotate refresh_token"
        )

        let claims = try decodeJWTPayload(refreshed.accessToken)
        #expect(claims["role"] as? String == "authenticated")
        #expect(claims["member_id"] as? String == LiveRefreshProofFixture.memberId)
        #expect(claims["gym_id"] as? String == LiveRefreshProofFixture.gymId)
        #expect(claims["app_role"] as? String == LiveRefreshProofFixture.appRole)

        // Advance the rotation chain with the new refresh (also proves it works).
        let second = try await GoTrueTokenRefresher.refresh(
            refreshToken: refreshed.refreshToken,
            supabaseURL: supabaseURL,
            publishableKey: LiveRefreshProofFixture.publishableKey
        )
        let secondClaims = try decodeJWTPayload(second.accessToken)
        #expect(secondClaims["member_id"] as? String == LiveRefreshProofFixture.memberId)
        #expect(secondClaims["app_role"] as? String == LiveRefreshProofFixture.appRole)

        // Past reuse interval + child used ⇒ parent is dead (genuine rotation).
        try await Task.sleep(for: Self.reuseInterval)

        do {
            _ = try await GoTrueTokenRefresher.refresh(
                refreshToken: oldRefresh,
                supabaseURL: supabaseURL,
                publishableKey: LiveRefreshProofFixture.publishableKey
            )
            Issue.record("Expected old refresh_token to be rejected after rotation")
        } catch let error as SyncError {
            guard case .sessionRefreshFailed = error else {
                Issue.record("Unexpected SyncError: \(error)")
                return
            }
            // expected — "Invalid Refresh Token: Already Used"
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    private func decodeJWTPayload(_ jwt: String) throws -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            throw SyncError.invalidBrokerToken("JWT missing payload")
        }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: base64),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.invalidBrokerToken("JWT payload decode failed")
        }
        return object
    }
}
