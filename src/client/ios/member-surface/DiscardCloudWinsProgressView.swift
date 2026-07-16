import SwiftUI

/// Progress / outcome for discard-cloud-wins clear + pull (#33).
struct DiscardCloudWinsProgressView: View {
    let result: DiscardCloudWinsResult?
    let isWorking: Bool
    var onDone: () -> Void
    var onRetryPull: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .sectionSpacing) {
            if isWorking {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                Text("Replacing this device’s history")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(
                    """
                    Clearing what’s on this phone, then downloading the account’s \
                    saved history. Keep the app open until it finishes.
                    """
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
            } else if let result, result.completed {
                Label("You’re connected", systemImage: "checkmark.circle.fill")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.green)

                Text("This device now shows the history saved to your TeamUp account.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                Button("Done", action: onDone)
                    .primaryButtonStyle(isEnabled: true)
                    .padding(.top, 8)
            } else if let result, result.clearedButPullIncomplete {
                Text("Connected — download didn’t finish")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(
                    """
                    What’s on this device was cleared, and you’re linked to the account. \
                    The account’s history is still in the cloud but hasn’t landed here yet.

                    \(result.errorMessage ?? "The download stopped early.")
                    """
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

                Text("Try again to download it, or use Sync now in Settings later. Nothing in the cloud was deleted.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button("Try downloading again", action: onRetryPull)
                        .primaryButtonStyle(isEnabled: true)
                    Button("Close", action: onDone)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.wolfBlue)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            } else {
                Text("Couldn’t replace this device’s history")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Text(
                    result?.errorMessage
                        ?? "Something went wrong before this device’s data was cleared. You’re still anonymous — nothing was lost."
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

                Button("Close", action: onDone)
                    .primaryButtonStyle(isEnabled: true)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Connecting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isWorking)
    }
}
