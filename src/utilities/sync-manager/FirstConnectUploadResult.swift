import Foundation

struct FirstConnectUploadCounts: Equatable, Sendable {
    var sessions: Int = 0
    var exerciseEntries: Int = 0
    var sets: Int = 0
    var personalBests: Int = 0

    var total: Int {
        sessions + exerciseEntries + sets + personalBests
    }
}

struct FirstConnectUploadResult: Equatable, Sendable {
    let counts: FirstConnectUploadCounts
    let completed: Bool
    let errorMessage: String?

    static func completed(counts: FirstConnectUploadCounts) -> FirstConnectUploadResult {
        FirstConnectUploadResult(counts: counts, completed: true, errorMessage: nil)
    }

    static func interrupted(counts: FirstConnectUploadCounts, error: Error) -> FirstConnectUploadResult {
        FirstConnectUploadResult(
            counts: counts,
            completed: false,
            errorMessage: error.localizedDescription
        )
    }
}
