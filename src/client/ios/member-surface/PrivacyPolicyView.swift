import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .sectionSpacing) {
                header
                section("Overview", body: overview)
                section("What Data the App Stores", body: dataStored)
                section("What We Do Not Do", body: whatWeDoNot)
                section("Data You Are in Control Of", body: dataControl)
                section("Children's Privacy", body: childrenPrivacy)
                section("Changes to This Policy", body: policyChanges)
                section("Future Versions", body: futureVersions)
                section("Contact", body: contact)
                Text("This privacy policy applies to GymPerformance version 1.0 and above.")
                    .captionLabelStyle()
                    .italic()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GymPerformance")
                .exerciseTitleStyle()
            Text("Last updated: May 2026")
                .captionLabelStyle()
            Text("Developer: LB Tech Consulting Ltd (registered in England and Wales)")
                .captionLabelStyle()
        }
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .exerciseTitleStyle()
            Text(body)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private let overview = """
    GymPerformance is designed with your privacy as a priority. All data you enter into the app is stored exclusively on your device. We do not collect, transmit, or share your personal data with anyone.
    """

    private let dataStored = """
    GymPerformance stores the following information locally on your device:

    • Training sessions — dates, exercises performed, sets, reps, weights, times, and distances
    • Personal bests — your best recorded performance for each exercise, including the date achieved
    • Calories — optional calorie figures you choose to enter
    • Your display name — used to identify your profile within the app

    This data is stored solely on your device using Apple's SwiftData framework. It does not leave your device.
    """

    private let whatWeDoNot = """
    • We do not collect your data
    • We do not transmit your data to any server or third party
    • We do not use your data for advertising or analytics
    • We do not share your data with anyone
    • We do not have access to any data you enter into the app
    """

    private let dataControl = """
    Because all data lives on your device, you are in full control:

    • Viewing your data — everything you enter is visible within the app
    • Deleting your data — deleting the app from your device permanently removes all data associated with it
    • Backing up your data — if you have iCloud Backup enabled on your device, app data may be included in your device backup. This is managed by Apple, not by us
    """

    private let childrenPrivacy = """
    GymPerformance is intended for use by adults. We do not knowingly collect data from anyone under the age of 13.
    """

    private let policyChanges = """
    If we update this privacy policy, the updated version will be included in a future app update. We will update the "Last updated" date at the top of this policy. Continued use of the app after an update constitutes acceptance of the revised policy.
    """

    private let futureVersions = """
    Future versions of GymPerformance may introduce features that store data on a central server — for example, to enable coach and owner views. If and when this happens, this privacy policy will be updated to reflect what data is collected, how it is stored, and your rights in relation to that data. You will be informed of any such changes before they take effect.
    """

    private let contact = """
    If you have any questions about this privacy policy or how your data is handled, please contact us at:

    LB Tech Consulting Ltd
    privacy@lbconsulting.tech
    """
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
