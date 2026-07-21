import Foundation

protocol TokenBrokerClient: Sendable {
    func mintStubSession(deviceMemberId: UUID) async throws -> BrokerSession
}

/// Calls the token-broker Edge Function with the same stub path as the web surface.
struct StubTeamUpTokenBroker: TokenBrokerClient {
    private let brokerURL: URL
    private let publishableKey: String
    private let urlSession: URLSession

    init(
        brokerURL: URL,
        publishableKey: String,
        urlSession: URLSession = .shared
    ) {
        self.brokerURL = brokerURL
        self.publishableKey = publishableKey
        self.urlSession = urlSession
    }

    func mintStubSession(deviceMemberId: UUID) async throws -> BrokerSession {
        StubBrokerReleaseGuard.assertStubBrokerAllowed()
        var request = URLRequest(url: brokerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = [
            "teamupToken": "stub-token",
            "deviceMemberId": deviceMemberId.uuidString,
            "surface": "ios",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.brokerRejected(statusCode: -1, detail: "No HTTP response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.brokerRejected(statusCode: http.statusCode, detail: detail)
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let access =
            (object?["access_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (object?["token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let access else {
            throw SyncError.invalidBrokerToken("Broker response did not include token")
        }

        let refresh = (object?["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let expiresAt: Date?
        if let expiresAtSeconds = object?["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresAtSeconds)
        } else if let expiresAtSeconds = object?["expires_at"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtSeconds))
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
