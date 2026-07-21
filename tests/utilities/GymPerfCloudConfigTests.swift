#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct GymPerfCloudConfigTests {
    @Test
    func configuredWhenUrlAndKeyPresentInEnvironment() {
        setenv("GYMPERF_SUPABASE_URL", "https://example.supabase.co", 1)
        setenv("GYMPERF_SUPABASE_PUBLISHABLE_KEY", "pk_test", 1)
        defer {
            unsetenv("GYMPERF_SUPABASE_URL")
            unsetenv("GYMPERF_SUPABASE_PUBLISHABLE_KEY")
        }

        #expect(GymPerfCloudConfig.isConfiguredForLiveSync)
        #expect(GymPerfCloudConfig.supabaseURL?.absoluteString == "https://example.supabase.co")
        #expect(GymPerfCloudConfig.publishableKey == "pk_test")
        #expect(GymPerfCloudConfig.tokenBrokerURL?.absoluteString.hasSuffix("/functions/v1/token-broker") == true)
    }

    @Test
    func testDeviceMemberIdIsEnvironmentOnlyInDebug() {
        let testId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        setenv("GYMPERF_TEST_DEVICE_MEMBER_ID", testId.uuidString, 1)
        defer { unsetenv("GYMPERF_TEST_DEVICE_MEMBER_ID") }

        #expect(GymPerfCloudConfig.testDeviceMemberId == testId)
    }

    #if DEBUG
    @Test
    func useRealOAuthReadsEnvironmentOnly() {
        setenv("GYMPERF_USE_REAL_OAUTH", "1", 1)
        defer { unsetenv("GYMPERF_USE_REAL_OAUTH") }
        #expect(GymPerfCloudConfig.useRealOAuth)
    }
    #endif
}

@Suite
struct StubBrokerReleaseGuardTests {
    @Test
    func stubBrokerAllowedOnlyInDebug() {
        #if DEBUG
        #expect(StubBrokerReleaseGuard.isStubBrokerAllowed)
        #else
        #expect(!StubBrokerReleaseGuard.isStubBrokerAllowed)
        #endif
    }

    @Test
    func releaseBlockedTokenBrokerRejectsMint() async {
        let broker = ReleaseBlockedTokenBroker()
        do {
            _ = try await broker.mintStubSession(deviceMemberId: UUID())
            Issue.record("Expected stub mint to be rejected")
        } catch SyncError.stubBrokerForbiddenInRelease {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite
struct ConnectFeatureAvailabilityTests {
    @Test
    func availableWhenCloudConfigured() {
        setenv("GYMPERF_SUPABASE_URL", "https://example.supabase.co", 1)
        setenv("GYMPERF_SUPABASE_PUBLISHABLE_KEY", "pk_test", 1)
        defer {
            unsetenv("GYMPERF_SUPABASE_URL")
            unsetenv("GYMPERF_SUPABASE_PUBLISHABLE_KEY")
        }

        #expect(ConnectFeatureAvailability.isAvailable)
    }
}
#endif
