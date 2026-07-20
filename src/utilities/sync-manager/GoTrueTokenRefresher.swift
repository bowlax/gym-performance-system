import Foundation

/// GoTrue refresh_token grant (#17). Rotates both access and refresh tokens.
enum GoTrueTokenRefresher {
    /// Injectable clock for tests (force near-expiry without waiting).
    static var now: () -> Date = { Date() }

    /// Refresh when access token expires within this window.
    static var skew: TimeInterval = 60

    /// Injectable session for tests.
    static var urlSession: URLSession = .shared

    struct RefreshedSession: Equatable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    static func needsRefresh(
        accessToken: String?,
        expiresAt: Date?,
        hasRefreshToken: Bool,
        now: Date = now()
    ) -> Bool {
        guard hasRefreshToken else { return false }
        guard let accessToken, !accessToken.isEmpty else { return true }
        guard let expiresAt else { return false }
        return expiresAt.addingTimeInterval(-skew) <= now
    }

    static func refresh(
        refreshToken: String,
        supabaseURL: URL,
        publishableKey: String
    ) async throws -> RefreshedSession {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        guard let url = components?.url else {
            throw SyncError.sessionRefreshFailed("Invalid GoTrue token URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["refresh_token": refreshToken]
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.sessionRefreshFailed("No HTTP response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.sessionRefreshFailed(
                "HTTP \(http.statusCode): \(detail)"
            )
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              !accessToken.isEmpty,
              let newRefresh = object["refresh_token"] as? String,
              !newRefresh.isEmpty else {
            throw SyncError.sessionRefreshFailed(
                "Refresh response missing access_token or refresh_token"
            )
        }

        let expiresAt: Date
        if let expiresAtSeconds = object["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresAtSeconds)
        } else if let expiresAtSeconds = object["expires_at"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtSeconds))
        } else if let expiresIn = object["expires_in"] as? Double {
            expiresAt = now().addingTimeInterval(expiresIn)
        } else if let expiresIn = object["expires_in"] as? Int {
            expiresAt = now().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            throw SyncError.sessionRefreshFailed("Refresh response missing expiry")
        }

        return RefreshedSession(
            accessToken: accessToken,
            refreshToken: newRefresh,
            expiresAt: expiresAt
        )
    }
}
