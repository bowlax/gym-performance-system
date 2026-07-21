import { createFileRoute, Link } from "@tanstack/react-router";
import { ChevronLeft } from "lucide-react";
import { AppShell } from "@/components/gp/app-shell";

export const Route = createFileRoute("/privacy")({
  head: () => ({
    meta: [
      { title: "Privacy Policy — GymPerformance" },
      {
        name: "description",
        content:
          "How GymPerformance handles your training data, account information, and privacy.",
      },
      { property: "og:title", content: "Privacy Policy — GymPerformance" },
      {
        property: "og:description",
        content:
          "How GymPerformance handles your training data, account information, and privacy.",
      },
      { property: "og:type", content: "article" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: PrivacyScreen,
});

function PrivacyScreen() {
  return (
    <AppShell>
      <div className="mb-6 flex items-center justify-between">
        <Link
          to="/"
          className="inline-flex items-center gap-1 text-sm font-medium text-primary"
        >
          <ChevronLeft className="size-4" />
          Back
        </Link>
        <h1 className="text-base font-semibold text-foreground">
          Privacy Policy
        </h1>
        <span className="w-12" aria-hidden />
      </div>

      <article className="prose prose-sm max-w-none text-foreground [&_h2]:mt-8 [&_h2]:text-base [&_h2]:font-semibold [&_h2]:text-foreground [&_h3]:mt-4 [&_h3]:text-sm [&_h3]:font-semibold [&_h3]:text-foreground [&_p]:mt-2 [&_p]:text-sm [&_p]:leading-relaxed [&_p]:text-muted-foreground [&_li]:text-sm [&_li]:leading-relaxed [&_li]:text-muted-foreground [&_td]:text-sm [&_td]:text-muted-foreground [&_th]:text-sm [&_a]:text-primary">
        <p className="text-muted-foreground">
          <strong className="text-foreground">Last updated: 21 July 2026</strong>
        </p>

        <p>
          This policy explains what information GymPerformance collects, why, and
          what choices you have. It applies to the GymPerformance app and its
          connected web features, used by members of Wolf Way of Life Fitness.
        </p>
        <p>
          If anything here is unclear, contact us at{" "}
          <a href="mailto:privacy@lbconsulting.tech">privacy@lbconsulting.tech</a>.
        </p>

        <h2>1. Who is responsible for your data</h2>
        <p>
          GymPerformance is provided by <strong>Wolf Way of Life Fitness</strong> (
          <strong>Way of Life Fitness Ltd</strong>), a gym based in Saffron Walden,
          UK, which decides what member data is collected and why (the data
          controller).
        </p>
        <p>
          The app itself is built and technically operated by{" "}
          <strong>LB Tech Consulting Ltd</strong> on Wolf Way of Life Fitness&apos;s
          behalf. LB Tech Consulting acts as a data processor, meaning it handles
          the technical systems but does not decide how your data is used.
        </p>
        <p>
          Contact for privacy questions or requests:{" "}
          <a href="mailto:privacy@lbconsulting.tech">privacy@lbconsulting.tech</a>{" "}
          (LB Tech Consulting).
        </p>

        <h2>2. What we collect</h2>
        <h3>If you never connect your account</h3>
        <p>
          If you use GymPerformance without connecting a TeamUp account, all your
          training data — sessions, sets, personal bests — stays on your device
          only. We do not receive, see, or store any of it. This policy&apos;s
          sections on data storage, third parties, and retention do not apply to
          you until you choose to connect.
        </p>

        <h3>If you connect your account</h3>
        <p>
          Connecting links your TeamUp membership to the app so your training
          history can back up to our systems, follow you across devices, and be
          visible to your coach. When you connect, we collect:
        </p>
        <ul>
          <li>
            <strong>Your TeamUp identity</strong> — a stable identifier from TeamUp
            (your TeamUp customer ID), which we use to recognise you across
            devices. We do not collect or store your TeamUp password; login
            happens directly with TeamUp.
          </li>
          <li>
            <strong>Your training data</strong> — exercises, sets, weights, reps,
            personal bests, and session dates that you log or that were logged
            with your knowledge (e.g. by a coach).
          </li>
          <li>
            <strong>App settings</strong> — preferences you set in the app, such as
            whether personal bests expire over time.
          </li>
          <li>
            <strong>Basic device/technical information</strong> needed to operate
            sync (e.g. a device identifier used only to coordinate your own data
            across your own devices — not used to track you across other apps or
            services).
          </li>
        </ul>
        <p>
          Separately from the app, Wolf Way of Life Fitness may contact you by{" "}
          <strong>email or WhatsApp</strong> in the ordinary course of gym
          membership and coaching. Those channels are not used by the app to
          collect training logs automatically.
        </p>
        <p>
          We do not collect payment information, health information beyond
          exercise performance, or location data. The app does not include
          analytics, advertising, or crash-reporting SDKs that send your data to
          other vendors.
        </p>

        <h2>3. Why we collect it, and our legal basis</h2>
        <div className="overflow-x-auto">
          <table>
            <thead>
              <tr>
                <th>What</th>
                <th>Why</th>
                <th>Legal basis</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Training data (connected)</td>
                <td>
                  To back up your history, sync it across your devices, and let it
                  be used within the app
                </td>
                <td>Your consent, given when you connect</td>
              </tr>
              <tr>
                <td>TeamUp identity</td>
                <td>
                  To recognise you as the same member across devices and link you
                  to your gym membership
                </td>
                <td>Your consent, given when you connect</td>
              </tr>
              <tr>
                <td>Data visible to your coach</td>
                <td>
                  So your coach can see your training progress and support you
                </td>
                <td>
                  Your consent, given when you connect — see Section 4
                </td>
              </tr>
              <tr>
                <td>App settings</td>
                <td>To make the app work the way you&apos;ve configured it</td>
                <td>
                  Your consent / legitimate interest in providing the service you
                  asked for
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p>
          Connecting your account <strong>is</strong> the moment you give this
          consent. Before you connect, nothing here applies. You can choose not to
          connect and keep using the app locally.
        </p>

        <h2>4. Who can see your data</h2>
        <ul>
          <li>
            <strong>You.</strong> Always, on any device where you&apos;re
            connected.
          </li>
          <li>
            <strong>Any coach at Wolf Way of Life Fitness.</strong> Coaches can
            view your training data to support your progress. Coaches have{" "}
            <strong>read-only</strong> access — they cannot edit or delete your
            training records.
          </li>
          <li>
            <strong>Steve (gym owner) and Lee (LB Tech Consulting)</strong> may
            also access connected training data as needed to run the gym and
            operate the systems — not to use it for advertising or unrelated
            purposes.
          </li>
          <li>
            <strong>Nobody else at the gym</strong>, unless you&apos;ve
            specifically arranged otherwise.
          </li>
          <li>
            <strong>LB Tech Consulting</strong> can access data only as needed to
            operate, maintain, and fix the systems that store it — not to look at
            your training data for any other purpose.
          </li>
        </ul>

        <h2>5. Where your data is stored</h2>
        <p>
          Your connected data is stored using <strong>Supabase</strong>, a
          database provider, in their <strong>eu-west-2 (London, UK)</strong> data
          centre. Identity verification uses <strong>TeamUp</strong>, your gym&apos;s
          membership platform. The app is distributed via{" "}
          <strong>Apple&apos;s App Store / TestFlight</strong>, which is subject to
          Apple&apos;s own privacy terms for app distribution.
        </p>
        <p>
          We do not sell, rent, or share your data with any other third party, and
          we do not use your data for advertising.
        </p>

        <h2>6. How long we keep your data</h2>
        <p>
          We keep your connected training data for as long as your gym membership
          and app connection are active, so your history remains available to you.
        </p>
        <p>
          If you&apos;d like your data deleted, contact us at{" "}
          <a href="mailto:privacy@lbconsulting.tech">privacy@lbconsulting.tech</a>{" "}
          and we will delete your account data. This is currently a manual process
          handled by request rather than an automatic in-app option — we&apos;re
          working on making this self-service in a future update.
        </p>
        <p>
          Disconnecting within the app is not yet available; contact us to
          disconnect and/or delete your data. When disconnect becomes available,
          disconnecting will <strong>not</strong> delete data already stored with
          us — it is retained until you request deletion, so that reconnecting
          later can restore your history.
        </p>

        <h2>7. Your rights</h2>
        <p>Under UK data protection law (UK GDPR), you have the right to:</p>
        <ul>
          <li>
            <strong>Access</strong> the data we hold about you
          </li>
          <li>
            <strong>Correct</strong> inaccurate data
          </li>
          <li>
            <strong>Delete</strong> your data (&quot;right to erasure&quot;)
          </li>
          <li>
            <strong>Restrict or object to</strong> certain processing
          </li>
          <li>
            <strong>Receive a copy</strong> of your data in a portable format
          </li>
          <li>
            <strong>Withdraw consent</strong> at any time (by disconnecting and/or
            requesting deletion — see Section 6)
          </li>
        </ul>
        <p>
          To exercise any of these rights, contact{" "}
          <a href="mailto:privacy@lbconsulting.tech">privacy@lbconsulting.tech</a>.
          We&apos;ll respond within one month, as required by law.
        </p>
        <p>
          If you&apos;re unhappy with how we&apos;ve handled your data, you can
          complain to the UK Information Commissioner&apos;s Office (ICO) at{" "}
          <a href="https://ico.org.uk">ico.org.uk</a>.
        </p>

        <h2>8. Children</h2>
        <p>
          GymPerformance is intended for gym members aged <strong>18</strong> and
          over. We do not knowingly collect data from anyone under 18. If you
          believe a child&apos;s data has been collected in error, contact us and
          we will delete it.
        </p>

        <h2>9. Security</h2>
        <p>
          We take reasonable technical measures to protect your data, including
          encrypted connections between the app and our servers, and access
          controls limiting who can view stored data. No system is completely
          secure, but we aim to follow good practice for a system of this size and
          sensitivity.
        </p>

        <h2>10. Changes to this policy</h2>
        <p>
          We may update this policy as the app changes — for example, when new
          features affecting your data (like account disconnection) become
          available. We&apos;ll update the &quot;Last updated&quot; date at the
          top, and for significant changes, we&apos;ll make reasonable efforts to
          let connected members know within the app.
        </p>

        <h2>11. Contact</h2>
        <p>Questions, requests, or concerns about your data:</p>
        <p>
          <strong>LB Tech Consulting Ltd</strong>
          <br />
          <a href="mailto:privacy@lbconsulting.tech">privacy@lbconsulting.tech</a>
        </p>
      </article>
    </AppShell>
  );
}
