import AuthenticationServices
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
/// DEBUG only — Release builds must use `OAuthConnectAuthClient`.
#if DEBUG
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
#endif

/// Production TeamUp OAuth client using ASWebAuthenticationSession (#17).
///
/// Opens the broker authorize URL in a system browser sheet. The broker
/// redirects TeamUp → exchanges code → mints Supabase JWT → redirects back
/// to `gymperformance://connect?access_token=...&refresh_token=...&expires_at=...&token=...`.
struct OAuthConnectAuthClient: ConnectAuthClient {
    static let callbackScheme = "gymperformance"
    static let callbackHost = "connect"
    static let callbackURL = "\(callbackScheme)://\(callbackHost)"

    private let brokerAuthorizeURL: URL
    private let publishableKey: String
    /// Injectable for tests — production uses ASWebAuthenticationSession.
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

    /// Convenience: creates an instance wired to ASWebAuthenticationSession.
    @MainActor
    init(brokerAuthorizeBaseURL: URL, publishableKey: String) {
        self.brokerAuthorizeURL = brokerAuthorizeBaseURL
        self.publishableKey = publishableKey
        self.openAuthorize = { url in
            try await Self.openWithASWebAuthSession(url: url)
        }
    }

    func authenticate(deviceMemberId: UUID) async throws -> BrokerSession {
        let authorizeURL = try Self.authorizeURL(
            brokerAuthorizeBaseURL: brokerAuthorizeURL,
            deviceMemberId: deviceMemberId
        )
        let callbackURL = try await openAuthorize(authorizeURL)
        return try Self.session(fromCallbackURL: callbackURL)
    }

    // MARK: - ASWebAuthenticationSession

    @MainActor
    private static func openWithASWebAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(
                        throwing: ASWebAuthenticationSessionError(
                            .canceledLogin
                        )
                    )
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = ASWebAuthPresentationContext.shared
            session.start()
        }
    }

    // MARK: - Callback parsing

    /// Parses broker redirect query params into a `BrokerSession`.
    ///
    /// Tolerates the "mangled" double-`?` form where an upstream redirect
    /// replaces `&` with a second `?` (same bug TeamUp's callback exhibited).
    /// Also reassembles JWTs whose `.` segments were split by `?` separators.
    /// Example: `gymperformance://connect?access_token=X?refresh_token=Y`
    static func session(fromCallbackURL url: URL) throws -> BrokerSession {
        let pairs = rawQueryPairs(from: url)
        var access: String?
        var refresh: String?
        var expiresAt: Date?

        var index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.hasPrefix("access_token=") {
                let raw = decodeQueryValue(String(pair.dropFirst("access_token=".count)))
                access = reassembleJWTIfNeeded(
                    startingWith: raw,
                    pairs: pairs,
                    index: &index
                )
            } else if pair.hasPrefix("token="), access == nil {
                let raw = decodeQueryValue(String(pair.dropFirst("token=".count)))
                access = reassembleJWTIfNeeded(
                    startingWith: raw,
                    pairs: pairs,
                    index: &index
                )
            } else if pair.hasPrefix("refresh_token=") {
                refresh = decodeQueryValue(String(pair.dropFirst("refresh_token=".count)))
            } else if pair.hasPrefix("expires_at=") {
                let raw = decodeQueryValue(String(pair.dropFirst("expires_at=".count)))
                if let seconds = Double(raw) {
                    expiresAt = Date(timeIntervalSince1970: seconds)
                }
            }
            index += 1
        }

        guard let access, JWTClaimsDecoder.isWellFormedJWT(access) else {
            throw SyncError.invalidBrokerToken("OAuth callback missing token")
        }

        return BrokerSession(
            token: JWTClaimsDecoder.normalizeToken(access),
            refreshToken: refresh.flatMap { $0.isEmpty ? nil : $0 },
            expiresAt: expiresAt
        )
    }

    static func authorizeURL(
        brokerAuthorizeBaseURL: URL,
        deviceMemberId: UUID
    ) throws -> URL {
        var components = URLComponents(
            url: brokerAuthorizeBaseURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "oauth", value: "authorize"),
            URLQueryItem(name: "deviceMemberId", value: deviceMemberId.uuidString),
            URLQueryItem(name: "surface", value: "ios"),
            URLQueryItem(name: "returnUrl", value: callbackURL),
        ]
        guard let authorizeURL = components?.url else {
            throw SyncError.cloudNotConfigured
        }
        return authorizeURL
    }

    /// Extracts query pairs robustly, handling the case where a second `?`
    /// appears instead of `&` (mangled redirect from upstream OAuth providers).
    private static func rawQueryPairs(from url: URL) -> [String] {
        let urlString = url.absoluteString

        guard let queryStart = urlString.firstIndex(of: "?") else { return [] }
        let queryString = String(urlString[urlString.index(after: queryStart)...])
        return queryString.components(separatedBy: CharacterSet(charactersIn: "&?"))
    }

    private static let knownQueryParamNames: Set<String> = [
        "access_token", "refresh_token", "expires_at", "token", "error",
    ]

    private static func isKnownParamPair(_ pair: String) -> Bool {
        guard let separator = pair.firstIndex(of: "=") else { return false }
        let name = String(pair[..<separator])
        return knownQueryParamNames.contains(name)
    }

    private static func decodeQueryValue(_ raw: String) -> String {
        raw.removingPercentEncoding ?? raw
    }

    /// When upstream mangling splits a JWT on `?` instead of `.`, stitch segments
    /// until we have header.payload.signature or hit the next known query param.
    private static func reassembleJWTIfNeeded(
        startingWith firstSegment: String,
        pairs: [String],
        index: inout Int
    ) -> String {
        var value = JWTClaimsDecoder.normalizeToken(firstSegment)
        while !JWTClaimsDecoder.isWellFormedJWT(value), index + 1 < pairs.count {
            let next = pairs[index + 1]
            if isKnownParamPair(next) { break }
            index += 1
            value += ".\(decodeQueryValue(next))"
        }
        return value
    }
}

// MARK: - ASWebAuthenticationSession presentation

private final class ASWebAuthPresentationContext: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    static let shared = ASWebAuthPresentationContext()

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window's scene window for the auth sheet.
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
