import Foundation

/// Gates the TeamUp connect flow (#31) and therefore sync triggers (#32).
///
/// **Why this exists:** the stub broker returns one shared identity
/// (`TEST-CUSTOMER-001`) to every caller. A Connect button in members' hands
/// would merge their histories. Real TeamUp auth is [#17](https://github.com/bowlax/gym-performance-system/issues/17).
/// Until then, Connect is simulator/dev only.
///
/// Sync inherits this fence: `SyncCoordinator` requires
/// `ConnectFeatureAvailability.isAvailable` and a usable connected session.
/// Release never connects → sync never fires. Anonymous (not connected) never syncs.
enum ConnectFeatureAvailability {
    /// `true` only in DEBUG builds that have `GYMPERF_*` cloud env configured.
    /// Release archives always return `false` — Connect UI is omitted.
    static var isAvailable: Bool {
        #if DEBUG
        GymPerfCloudConfig.isConfiguredForLiveSync
        #else
        false
        #endif
    }
}
