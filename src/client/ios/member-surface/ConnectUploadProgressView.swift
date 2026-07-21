import SwiftUI

struct ConnectUploadProgressView: View {
    let result: SyncCycleResult?
    let isSyncing: Bool
    var onDone: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .sectionSpacing) {
            if isSyncing {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                Text(ConnectSyncProgressCopy.runningTitle())
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(ConnectSyncProgressCopy.runningDetail())
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if let result, result.completed {
                Label("You’re connected", systemImage: "checkmark.circle.fill")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.green)

                Text(
                    ConnectSyncProgressCopy.completedMessage(
                        pulled: result.pull.mergeCounts.total,
                        pushed: result.push.counts.total
                    )
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

                Button("Done", action: onDone)
                    .primaryButtonStyle(isEnabled: true)
                    .padding(.top, 8)
            } else {
                Text(result.map(ConnectSyncProgressCopy.failureTitle) ?? "Sync didn’t finish")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(
                    result.map(ConnectSyncProgressCopy.failureMessage)
                        ?? "Something stopped the sync. Try again when you’re ready."
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

                if let result {
                    Text(ConnectSyncProgressCopy.failureFootnote(result: result))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Button("Try again", action: onRetry)
                        .primaryButtonStyle(isEnabled: true)
                    Button("Close", action: onDone)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.wolfBlue)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Syncing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSyncing)
    }
}
