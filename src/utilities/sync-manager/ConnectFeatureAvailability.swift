import Foundation

/// Gates the TeamUp connect flow (#31) and therefore sync triggers (#32).
///
/// **Why this exists:** connect must not appear unless cloud config is deliberately
/// baked into the build (Release xcconfig → Info.plist) or supplied for dev (DEBUG
/// scheme env). The stub broker remains DEBUG-only; Release always uses real OAuth.
///
/// Sync inherits this fence: `SyncCoordinator` requires
/// `ConnectFeatureAvailability.isAvailable` and a usable connected session.
enum ConnectFeatureAvailability {
    /// `true` when Supabase URL and publishable key are configured.
    static var isAvailable: Bool {
        GymPerfCloudConfig.isConfiguredForLiveSync
    }
}
