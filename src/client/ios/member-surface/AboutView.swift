import SwiftUI

struct AboutView: View {
    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GymPerformance")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(versionLine)
                        .captionLabelStyle()
                    Text("LB Tech Consulting Ltd")
                        .captionLabelStyle()
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Built for members and coaches at the gym — personal bests, sessions, and progression.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
