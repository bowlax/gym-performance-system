import Foundation

enum SyncError: Error, LocalizedError, Equatable {
    case cloudNotConfigured
    case invalidBrokerToken(String)
    case brokerRejected(statusCode: Int, detail: String)
    case uploadFailed(table: String, statusCode: Int, detail: String)
    case pullFailed(table: String, statusCode: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .cloudNotConfigured:
            return "Cloud sync is not configured. Set GYMPERF_SUPABASE_URL, GYMPERF_SUPABASE_PUBLISHABLE_KEY, and GYMPERF_TEST_DEVICE_MEMBER_ID."
        case .invalidBrokerToken(let detail):
            return "Broker token is invalid: \(detail)"
        case .brokerRejected(let statusCode, let detail):
            return "Token broker rejected the request (\(statusCode)): \(detail)"
        case .uploadFailed(let table, let statusCode, let detail):
            return "Upload to \(table) failed (\(statusCode)): \(detail)"
        case .pullFailed(let table, let statusCode, let detail):
            return "Pull from \(table) failed (\(statusCode)): \(detail)"
        }
    }
}
