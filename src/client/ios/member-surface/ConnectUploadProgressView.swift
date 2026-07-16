import SwiftUI

struct ConnectUploadProgressView: View {
    let result: FirstConnectUploadResult?
    let isUploading: Bool
    var onDone: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .sectionSpacing) {
            if isUploading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                Text("Uploading your training history")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(
                    """
                    This can take a while if you’ve logged a lot. Keep the app open \
                    until it finishes — if it’s interrupted, your history stays on \
                    this device and you can continue from Settings.
                    """
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
            } else if let result, result.completed {
                Label("You’re connected", systemImage: "checkmark.circle.fill")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.green)

                Text(completedCopy(counts: result.counts))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                Button("Done", action: onDone)
                    .primaryButtonStyle(isEnabled: true)
                    .padding(.top, 8)
            } else {
                Text("Upload didn’t finish")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(
                    result?.errorMessage
                        ?? "Something stopped the upload. Nothing was lost on this device — try again when you’re ready."
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

                Text("What already uploaded stays uploaded; the rest will continue next time.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)

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
        .navigationBarBackButtonHidden(isUploading)
    }

    private func completedCopy(counts: FirstConnectUploadCounts) -> String {
        if counts.total == 0 {
            return "You’re linked. There wasn’t anything new to upload from this device."
        }
        return "Uploaded \(counts.total) records from this device. You’re set."
    }
}
