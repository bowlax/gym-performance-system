import SwiftUI

/// Discard-cloud-wins choice (#31 / #33). Not a dismissible dialog —
/// connecting will replace this device’s anonymous history with the account’s
/// cloud data. Cancel keeps the member anonymous with data intact.
struct DiscardCloudWinsView: View {
    var onProceed: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .sectionSpacing) {
            Text("This account already has training history")
                .font(.system(.title2, design: .rounded).weight(.semibold))

            Text(
                """
                Connecting will use the history already saved to this TeamUp account \
                and replace what’s on this device.

                The sessions and personal bests logged on this phone while you were \
                offline will not be kept.
                """
            )
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.primary)

            Text("If you’re not sure, cancel and stay on this device only. You can connect later from Settings.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button("Replace this device’s history and connect", action: onProceed)
                    .primaryButtonStyle(isEnabled: true)

                Button("Cancel — keep this device as it is", action: onCancel)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.wolfBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .navigationTitle("Before you connect")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}
