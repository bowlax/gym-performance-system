import Foundation

/// User-facing connect sync outcome copy (#31 / second-device pull).
enum ConnectSyncProgressCopy {
    static func runningTitle() -> String {
        "Syncing with your account…"
    }

    static func runningDetail() -> String {
        """
        This can take a while if you’ve logged a lot. Keep the app open \
        until it finishes — if it’s interrupted, you can try again from Settings.
        """
    }

    static func completedMessage(pulled: Int, pushed: Int) -> String {
        switch (pulled, pushed) {
        case (0, 0):
            return "You’re connected."
        case (0, let pushed) where pushed > 0:
            return "Uploaded \(pushed) records from this device. You’re set."
        case (let pulled, 0) where pulled > 0:
            return "Downloaded your training history. You’re connected."
        case (let pulled, let pushed):
            return "Synced with your account — downloaded \(pulled) and uploaded \(pushed) records."
        }
    }

    static func failureTitle(result: SyncCycleResult) -> String {
        if !result.pull.completed {
            return "Download didn’t finish"
        }
        return "Sync didn’t finish"
    }

    static func failureMessage(result: SyncCycleResult) -> String {
        if !result.pull.completed {
            return result.pull.errorMessage
                ?? "Something stopped the download. Try again when you’re ready."
        }
        return result.push.errorMessage
            ?? "Something stopped the sync. Try again when you’re ready."
    }

    static func failureFootnote(result: SyncCycleResult) -> String {
        if !result.pull.completed {
            return "Nothing on this device was changed yet."
        }
        if result.pull.mergeCounts.total > 0 {
            return "What already downloaded stays on this device; the rest will continue next time."
        }
        return "What already uploaded stays uploaded; the rest will continue next time."
    }
}
