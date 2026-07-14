import Foundation

enum SyncConstants {
    /// Number of records per PostgREST upsert request during first-connect push.
    static let uploadBatchSize = 50
}
