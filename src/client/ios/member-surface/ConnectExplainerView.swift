import SwiftUI

/// Copy and layout for the connect explainer (#31).
///
/// Straight about the deal: data goes to the gym, coaches can see it,
/// it follows devices, and web becomes available. Connecting is a choice —
/// declining is unpenalised.
struct ConnectExplainerView: View {
    var onConnect: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .sectionSpacing) {
                Text("Connect your account")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))

                Text("Linking with TeamUp lets your training follow you — and lets your gym coach see how you’re doing.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    bullet(
                        title: "Your training is stored with the gym",
                        detail: "Sessions and personal bests sync to the gym’s system instead of living only on this phone."
                    )
                    bullet(
                        title: "Your coach can see your progress",
                        detail: "That’s the main reason gyms want sync — so coaching isn’t guessing from memory."
                    )
                    bullet(
                        title: "It follows you across devices",
                        detail: "A new phone or the web app can pick up where you left off."
                    )
                    bullet(
                        title: "You can use the web app",
                        detail: "Same account, same history — useful when you’re not carrying your phone into the gym."
                    )
                }
                .standardCard()

                Text("You can stay on this device only. Connecting is optional, and you can come back to it later in Settings.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button("Connect with TeamUp", action: onConnect)
                        .primaryButtonStyle(isEnabled: true)

                    Button("Not now", action: onNotNow)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.wolfBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(detail)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
