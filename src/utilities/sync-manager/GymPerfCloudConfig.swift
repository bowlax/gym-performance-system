import Foundation

/// Runtime configuration for cloud sync and the token broker (#17 / Build 13).
///
/// Layered resolution:
/// - **DEBUG:** `ProcessInfo.environment` → Info.plist → nil
/// - **RELEASE:** Info.plist → nil
enum GymPerfCloudConfig {
    static var supabaseURL: URL? {
        resolvedString(for: "GYMPERF_SUPABASE_URL").flatMap(URL.init(string:))
    }

    static var publishableKey: String? {
        resolvedString(for: "GYMPERF_SUPABASE_PUBLISHABLE_KEY")
    }

    /// DEBUG/test-only override for stub broker and integration harnesses.
    static var testDeviceMemberId: UUID? {
        #if DEBUG
        environmentOnlyString(for: "GYMPERF_TEST_DEVICE_MEMBER_ID")
            .flatMap(UUID.init(uuidString:))
        #else
        nil
        #endif
    }

    static var tokenBrokerURL: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/token-broker")
    }

    static var isConfiguredForLiveSync: Bool {
        supabaseURL != nil && publishableKey != nil
    }

    #if DEBUG
    /// When true, ConnectFlowService uses OAuthConnectAuthClient. When false, stub broker.
    /// Set `GYMPERF_USE_REAL_OAUTH=1` in your Xcode scheme environment.
    static var useRealOAuth: Bool {
        environmentOnlyString(for: "GYMPERF_USE_REAL_OAUTH") == "1"
    }
    #endif

    private static func resolvedString(for key: String) -> String? {
        #if DEBUG
        if let env = trimmedNonEmpty(ProcessInfo.processInfo.environment[key]) {
            return env
        }
        #endif
        return infoPlistString(for: key)
    }

    #if DEBUG
    private static func environmentOnlyString(for key: String) -> String? {
        trimmedNonEmpty(ProcessInfo.processInfo.environment[key])
    }
    #endif

    private static func infoPlistString(for key: String) -> String? {
        trimmedNonEmpty(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Unsubstituted build-setting placeholders in Info.plist mean "not configured".
        if trimmed.hasPrefix("$("), trimmed.hasSuffix(")") { return nil }
        return trimmed
    }
}
