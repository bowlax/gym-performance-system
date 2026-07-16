import SwiftUI

/// Launch prompts for connect (#31).
///
/// Rationale: this is not a growth nudge. A member who declines and then logs
/// sessions locally becomes the discard-cloud-wins case later — their local
/// data is destroyed when they eventually connect. Asking before they
/// accumulate data is how that path is avoided.
///
/// "Don't ask again" is local state. It will not survive a reinstall — that
/// is correct, since a reinstall is also when cloud data might be waiting.
///
/// Never-connected and session-expired are DISTINCT prompts with distinct copy.
struct ConnectLaunchPromptsModifier: ViewModifier {
    @Environment(AppDependencies.self) private var dependencies

    @State private var showNeverConnected = false
    @State private var showSessionExpired = false
    @State private var showConnectFlow = false

    func body(content: Content) -> some View {
        content
            .task {
                evaluatePrompts()
            }
            .sheet(isPresented: $showNeverConnected) {
                // Fixed detents: measuring content height via PreferenceKey +
                // .presentationDetents([.height(measured)]) collapsed to ~0
                // because the sheet laid out before the preference fired.
                // .medium shows the short copy reliably; .large is a fallback
                // if Dynamic Type / accessibility needs more room.
                NeverConnectedPromptSheet(
                    onConnect: {
                        showNeverConnected = false
                        showConnectFlow = true
                    },
                    onNotNow: {
                        showNeverConnected = false
                    },
                    onDontAskAgain: {
                        MemberConnectionStore.dontAskConnectAgain = true
                        showNeverConnected = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSessionExpired) {
                SessionExpiredPromptSheet(
                    onReconnect: {
                        showSessionExpired = false
                        showConnectFlow = true
                    },
                    onLater: {
                        showSessionExpired = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showConnectFlow) {
                ConnectFlowView()
            }
    }

    private func evaluatePrompts() {
        guard ConnectFeatureAvailability.isAvailable else { return }

        if MemberConnectionStore.sessionNeedsReauth {
            showSessionExpired = true
            return
        }

        if !MemberConnectionStore.isConnected && !MemberConnectionStore.dontAskConnectAgain {
            showNeverConnected = true
        }
    }
}

extension View {
    func connectLaunchPrompts() -> some View {
        modifier(ConnectLaunchPromptsModifier())
    }
}

/// Never connected — offer before local history piles up.
private struct NeverConnectedPromptSheet: View {
    var onConnect: () -> Void
    var onNotNow: () -> Void
    var onDontAskAgain: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: .sectionSpacing) {
                Text("Connect when you’re ready")
                    .font(.system(.title2, design: .rounded).weight(.semibold))

                Text(
                    "Your training data stays on this device unless you connect. Connecting with TeamUp backs up your history and lets your coach see your progress."
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button("Connect with TeamUp", action: onConnect)
                        .primaryButtonStyle(isEnabled: true)
                    Button("Not now", action: onNotNow)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.wolfBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    Button("Don’t ask again", action: onDontAskAgain)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onNotNow)
                        .foregroundStyle(Color.wolfBlue)
                }
            }
        }
        .tint(Color.wolfBlue)
    }
}

/// Connected member whose session expired — not the same as never connected.
private struct SessionExpiredPromptSheet: View {
    var onReconnect: () -> Void
    var onLater: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: .sectionSpacing) {
                Text("Sign in again")
                    .font(.system(.title2, design: .rounded).weight(.semibold))

                Text(
                    """
                    Your connection to the gym needs refreshing. This isn’t asking you \
                    to set up sync for the first time — you’re already linked; the \
                    sign-in just expired.
                    """
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button("Sign in again", action: onReconnect)
                        .primaryButtonStyle(isEnabled: true)
                    Button("Later", action: onLater)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.wolfBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onLater)
                        .foregroundStyle(Color.wolfBlue)
                }
            }
        }
        .tint(Color.wolfBlue)
    }
}
