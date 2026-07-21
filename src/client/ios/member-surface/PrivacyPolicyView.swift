import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .sectionSpacing) {
                header
                intro
                section("1. Who is responsible for your data", body: whoResponsible)
                section("2. What we collect", body: whatWeCollect)
                section("3. Why we collect it, and our legal basis", body: legalBasis)
                section("4. Who can see your data", body: whoCanSee)
                section("5. Where your data is stored", body: whereStored)
                section("6. How long we keep your data", body: retention)
                section("7. Your rights", body: rights)
                section("8. Children", body: children)
                section("9. Security", body: security)
                section("10. Changes to this policy", body: changes)
                section("11. Contact", body: contact)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GymPerformance Privacy Policy")
                .exerciseTitleStyle()
            Text("Last updated: 21 July 2026")
                .captionLabelStyle()
        }
    }

    private var intro: some View {
        Text(
            """
            This policy explains what information GymPerformance collects, why, and what choices you have. It applies to the GymPerformance app and its connected web features, used by members of Wolf Way of Life Fitness.

            If anything here is unclear, contact us at privacy@lbconsulting.tech.
            """
        )
        .font(.system(.body, design: .rounded))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
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

    private let whoResponsible = """
    GymPerformance is provided by Wolf Way of Life Fitness (Way of Life Fitness Ltd), a gym based in Saffron Walden, UK, which decides what member data is collected and why (the data controller).

    The app itself is built and technically operated by LB Tech Consulting Ltd on Wolf Way of Life Fitness's behalf. LB Tech Consulting acts as a data processor, meaning it handles the technical systems but does not decide how your data is used.

    Contact for privacy questions or requests: privacy@lbconsulting.tech (LB Tech Consulting).
    """

    private let whatWeCollect = """
    If you never connect your account

    If you use GymPerformance without connecting a TeamUp account, all your training data — sessions, sets, personal bests — stays on your device only. We do not receive, see, or store any of it. This policy's sections on data storage, third parties, and retention do not apply to you until you choose to connect.

    If you connect your account

    Connecting links your TeamUp membership to the app so your training history can back up to our systems, follow you across devices, and be visible to your coach. When you connect, we collect:

    • Your TeamUp identity — a stable identifier from TeamUp (your TeamUp customer ID), which we use to recognise you across devices. We do not collect or store your TeamUp password; login happens directly with TeamUp.
    • Your training data — exercises, sets, weights, reps, personal bests, and session dates that you log or that were logged with your knowledge (e.g. by a coach).
    • App settings — preferences you set in the app, such as whether personal bests expire over time.
    • Basic device/technical information needed to operate sync (e.g. a device identifier used only to coordinate your own data across your own devices — not used to track you across other apps or services).

    Separately from the app, Wolf Way of Life Fitness may contact you by email or WhatsApp in the ordinary course of gym membership and coaching. Those channels are not used by the app to collect training logs automatically.

    We do not collect payment information, health information beyond exercise performance, or location data. The app does not include analytics, advertising, or crash-reporting SDKs that send your data to other vendors.
    """

    private let legalBasis = """
    Training data (connected) — to back up your history, sync it across your devices, and let it be used within the app. Legal basis: your consent, given when you connect.

    TeamUp identity — to recognise you as the same member across devices and link you to your gym membership. Legal basis: your consent, given when you connect.

    Data visible to your coach — so your coach can see your training progress and support you. Legal basis: your consent, given when you connect — see Section 4.

    App settings — to make the app work the way you've configured it. Legal basis: your consent / legitimate interest in providing the service you asked for.

    Connecting your account is the moment you give this consent. Before you connect, nothing here applies. You can choose not to connect and keep using the app locally.
    """

    private let whoCanSee = """
    • You. Always, on any device where you're connected.
    • Any coach at Wolf Way of Life Fitness. Coaches can view your training data to support your progress. Coaches have read-only access — they cannot edit or delete your training records.
    • Steve (gym owner) and Lee (LB Tech Consulting) may also access connected training data as needed to run the gym and operate the systems — not to use it for advertising or unrelated purposes.
    • Nobody else at the gym, unless you've specifically arranged otherwise.
    • LB Tech Consulting can access data only as needed to operate, maintain, and fix the systems that store it — not to look at your training data for any other purpose.
    """

    private let whereStored = """
    Your connected data is stored using Supabase, a database provider, in their eu-west-2 (London, UK) data centre. Identity verification uses TeamUp, your gym's membership platform. The app is distributed via Apple's App Store / TestFlight, which is subject to Apple's own privacy terms for app distribution.

    We do not sell, rent, or share your data with any other third party, and we do not use your data for advertising.
    """

    private let retention = """
    We keep your connected training data for as long as your gym membership and app connection are active, so your history remains available to you.

    If you'd like your data deleted, contact us at privacy@lbconsulting.tech and we will delete your account data. This is currently a manual process handled by request rather than an automatic in-app option — we're working on making this self-service in a future update.

    Disconnecting within the app is not yet available; contact us to disconnect and/or delete your data. When disconnect becomes available, disconnecting will not delete data already stored with us — it is retained until you request deletion, so that reconnecting later can restore your history.
    """

    private let rights = """
    Under UK data protection law (UK GDPR), you have the right to:

    • Access the data we hold about you
    • Correct inaccurate data
    • Delete your data ("right to erasure")
    • Restrict or object to certain processing
    • Receive a copy of your data in a portable format
    • Withdraw consent at any time (by disconnecting and/or requesting deletion — see Section 6)

    To exercise any of these rights, contact privacy@lbconsulting.tech. We'll respond within one month, as required by law.

    If you're unhappy with how we've handled your data, you can complain to the UK Information Commissioner's Office (ICO) at ico.org.uk.
    """

    private let children = """
    GymPerformance is intended for gym members aged 18 and over. We do not knowingly collect data from anyone under 18. If you believe a child's data has been collected in error, contact us and we will delete it.
    """

    private let security = """
    We take reasonable technical measures to protect your data, including encrypted connections between the app and our servers, and access controls limiting who can view stored data. No system is completely secure, but we aim to follow good practice for a system of this size and sensitivity.
    """

    private let changes = """
    We may update this policy as the app changes — for example, when new features affecting your data (like account disconnection) become available. We'll update the "Last updated" date at the top, and for significant changes, we'll make reasonable efforts to let connected members know within the app.
    """

    private let contact = """
    Questions, requests, or concerns about your data:

    LB Tech Consulting Ltd
    privacy@lbconsulting.tech
    """
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
