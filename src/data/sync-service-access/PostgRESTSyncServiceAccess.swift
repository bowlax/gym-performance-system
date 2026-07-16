import Foundation

/// PostgREST client for member-JWT pull and idempotent UUID-keyed upserts.
struct PostgRESTSyncServiceAccess: SyncServiceAccess {
    private let credentials: SyncCredentials
    private let urlSession: URLSession

    init(credentials: SyncCredentials, urlSession: URLSession = .shared) {
        self.credentials = credentials
        self.urlSession = urlSession
    }

    func upsertSessions(_ rows: [[String: Any]]) async throws {
        try await upsert(table: "sessions", rows: rows)
    }

    func upsertExerciseEntries(_ rows: [[String: Any]]) async throws {
        try await upsert(table: "exercise_entries", rows: rows)
    }

    func upsertSets(_ rows: [[String: Any]]) async throws {
        try await upsert(table: "sets", rows: rows)
    }

    func upsertPersonalBests(_ rows: [[String: Any]]) async throws {
        try await upsert(table: "personal_bests", rows: rows)
    }

    func upsertExerciseResets(_ rows: [[String: Any]]) async throws {
        try await upsert(table: "exercise_resets", rows: rows)
    }

    func patchMemberSettings(memberId: UUID, fields: [String: Any]) async throws -> Bool {
        var components = URLComponents(
            url: credentials.restAPIBaseURL.appendingPathComponent("members"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(memberId.uuidString)"),
        ]

        guard let url = components?.url else {
            throw SyncError.uploadFailed(table: "members", statusCode: -1, detail: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        // Representation so zero-row matches are visible (empty JSON array), not papered over.
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.uploadFailed(table: "members", statusCode: -1, detail: "No HTTP response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.uploadFailed(table: "members", statusCode: http.statusCode, detail: detail)
        }

        let json = try JSONSerialization.jsonObject(with: data)
        guard let rows = json as? [[String: Any]] else {
            throw SyncError.uploadFailed(
                table: "members",
                statusCode: http.statusCode,
                detail: "Expected JSON array representation after PATCH"
            )
        }
        return !rows.isEmpty
    }

    func pullSessions(since: Date?) async throws -> [CloudSessionRow] {
        let data = try await get(table: "sessions", since: since)
        return try CloudRowDecoder.decodeSessions(from: data)
    }

    func pullExerciseEntries(since: Date?) async throws -> [CloudExerciseEntryRow] {
        let data = try await get(table: "exercise_entries", since: since)
        return try CloudRowDecoder.decodeExerciseEntries(from: data)
    }

    func pullSets(since: Date?) async throws -> [CloudSetRow] {
        let data = try await get(table: "sets", since: since)
        return try CloudRowDecoder.decodeSets(from: data)
    }

    func pullPersonalBests(since: Date?) async throws -> [CloudPersonalBestRow] {
        let data = try await get(table: "personal_bests", since: since)
        return try CloudRowDecoder.decodePersonalBests(from: data)
    }

    func pullMembers(since: Date?) async throws -> [CloudMemberRow] {
        let data = try await get(table: "members", since: since)
        return try CloudRowDecoder.decodeMembers(from: data)
    }

    func pullExerciseResets(since: Date?) async throws -> [CloudExerciseResetRow] {
        let data = try await get(table: "exercise_resets", since: since)
        return try CloudRowDecoder.decodeExerciseResets(from: data)
    }

    private func upsert(table: String, rows: [[String: Any]]) async throws {
        guard !rows.isEmpty else { return }

        var components = URLComponents(
            url: credentials.restAPIBaseURL.appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]

        guard let url = components?.url else {
            throw SyncError.uploadFailed(table: table, statusCode: -1, detail: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: rows)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.uploadFailed(table: table, statusCode: -1, detail: "No HTTP response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.uploadFailed(table: table, statusCode: http.statusCode, detail: detail)
        }
    }

    private func get(table: String, since: Date?) async throws -> Data {
        var components = URLComponents(
            url: credentials.restAPIBaseURL.appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "synced_at.asc.nullslast"),
        ]
        if let since {
            queryItems.append(URLQueryItem(name: "synced_at", value: "gt.\(iso8601(since))"))
        } else {
            // First pull: only rows that carry a cloud-authoritative synced_at watermark.
            queryItems.append(URLQueryItem(name: "synced_at", value: "not.is.null"))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw SyncError.pullFailed(table: table, statusCode: -1, detail: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.pullFailed(table: table, statusCode: -1, detail: "No HTTP response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.pullFailed(table: table, statusCode: http.statusCode, detail: detail)
        }
        return data
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
