import Foundation

/// Runtime configuration for cloud sync and the token broker.
///
/// Values are read from the process environment (Xcode scheme / `xcodebuild`
/// test env) so the same build can target local or hosted Supabase without
/// embedding secrets in source.
enum GymPerfCloudConfig {
    static var supabaseURL: URL? {
        stringValue(for: "GYMPERF_SUPABASE_URL").flatMap(URL.init(string:))
    }

    static var publishableKey: String? {
        stringValue(for: "GYMPERF_SUPABASE_PUBLISHABLE_KEY")
    }

    static var testDeviceMemberId: UUID? {
        stringValue(for: "GYMPERF_TEST_DEVICE_MEMBER_ID").flatMap(UUID.init(uuidString:))
    }

    static var tokenBrokerURL: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/token-broker")
    }

    static var isConfiguredForLiveSync: Bool {
        supabaseURL != nil && publishableKey != nil && testDeviceMemberId != nil
    }

    private static func stringValue(for key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
