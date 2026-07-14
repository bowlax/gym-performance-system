import Foundation

struct SyncCycleResult: Equatable, Sendable {
    let pull: SyncPullResult
    let push: FirstConnectUploadResult

    var completed: Bool {
        pull.completed && push.completed
    }

    var errorMessage: String? {
        if !pull.completed { return pull.errorMessage }
        if !push.completed { return push.errorMessage }
        return nil
    }
}
