import Foundation

/// Obtains a broker JWT after the member chooses to connect (#31).
///
/// Real TeamUp auth (#17) opens the broker authorize route in a browser and
/// returns with a token. The stub path mints immediately. UI calls only this
/// protocol — swapping implementations must not restructure screens.
protocol ConnectAuthClient: Sendable {
    func authenticate(deviceMemberId: UUID) async throws -> BrokerSession
}

/// Dev/simulator auth against the stub broker. Same shape as production:
/// call `authenticate` → receive `BrokerSession`.
struct StubConnectAuthClient: ConnectAuthClient {
    private let broker: StubTeamUpTokenBroker

    init(broker: StubTeamUpTokenBroker) {
        self.broker = broker
    }

    init(brokerURL: URL, publishableKey: String) {
        self.broker = StubTeamUpTokenBroker(
            brokerURL: brokerURL,
            publishableKey: publishableKey
        )
    }

    func authenticate(deviceMemberId: UUID) async throws -> BrokerSession {
        try await broker.mintStubSession(deviceMemberId: deviceMemberId)
    }
}

/// Production-shaped client for TeamUp OAuth via the broker (#17).
/// Builds the authorize URL and parses `?token=` from the return URL.
/// Not wired to `ASWebAuthenticationSession` until #17 lands — UI can still
/// depend on `ConnectAuthClient` without knowing which implementation runs.
struct OAuthConnectAuthClient: ConnectAuthClient {
    private let brokerAuthorizeURL: URL
    private let publishableKey: String
    /// Opens the authorize URL and returns the redirect callback URL.
    private let openAuthorize: @Sendable (URL) async throws -> URL

    init(
        brokerAuthorizeBaseURL: URL,
        publishableKey: String,
        openAuthorize: @escaping @Sendable (URL) async throws -> URL
    ) {
        self.brokerAuthorizeURL = brokerAuthorizeBaseURL
        self.publishableKey = publishableKey
        self.openAuthorize = openAuthorize
    }

    func authenticate(deviceMemberId: UUID) async throws -> BrokerSession {
        var components = URLComponents(
            url: brokerAuthorizeURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "oauth", value: "authorize"),
            URLQueryItem(name: "deviceMemberId", value: deviceMemberId.uuidString),
            URLQueryItem(name: "surface", value: "ios"),
        ]
        guard let authorizeURL = components?.url else {
            throw SyncError.cloudNotConfigured
        }

        let callbackURL = try await openAuthorize(authorizeURL)
        return try Self.session(fromCallbackURL: callbackURL)
    }

    /// Parses broker redirect query params into a `BrokerSession`.
    ///
    /// Auth path (#17): `access_token`, `refresh_token`, `expires_at`, and
    /// `token` (alias of access). Stub/legacy: `token` only.
    static func session(fromCallbackURL url: URL) throws -> BrokerSession {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SyncError.invalidBrokerToken("OAuth callback missing token")
        }
        let items = components.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        let access =
            query("access_token").flatMap { $0.isEmpty ? nil : $0 }
            ?? query("token").flatMap { $0.isEmpty ? nil : $0 }
        guard let access else {
            throw SyncError.invalidBrokerToken("OAuth callback missing token")
        }

        let refresh = query("refresh_token").flatMap { $0.isEmpty ? nil : $0 }

        let expiresAt: Date?
        if let raw = query("expires_at"), let seconds = Double(raw) {
            expiresAt = Date(timeIntervalSince1970: seconds)
        } else {
            expiresAt = nil
        }

        return BrokerSession(
            token: access,
            refreshToken: refresh,
            expiresAt: expiresAt
        )
    }
}
