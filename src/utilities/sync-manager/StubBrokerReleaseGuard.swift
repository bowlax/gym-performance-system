import Foundation

/// Belt-and-braces guard: the stub broker shares one TeamUp identity across all
/// callers. It must never mint tokens in a Release/TestFlight build.
enum StubBrokerReleaseGuard {
    #if DEBUG
    static let isStubBrokerAllowed = true
    #else
    static let isStubBrokerAllowed = false
    #endif

    static func assertStubBrokerAllowed(
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #if !DEBUG
        preconditionFailure(
            "Stub broker must never run in Release builds",
            file: file,
            line: line
        )
        #endif
    }
}

/// Release stand-in for `TokenBrokerClient`. Production sync uses real broker
/// sessions from OAuth; this type exists only so `SyncManager` can compile.
/// Minting a stub session is forbidden and trapped at runtime.
struct ReleaseBlockedTokenBroker: TokenBrokerClient {
    func mintStubSession(deviceMemberId: UUID) async throws -> BrokerSession {
        StubBrokerReleaseGuard.assertStubBrokerAllowed()
        throw SyncError.stubBrokerForbiddenInRelease
    }
}
