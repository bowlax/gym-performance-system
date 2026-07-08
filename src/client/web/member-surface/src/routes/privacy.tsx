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

      <article className="prose prose-sm max-w-none text-foreground [&_p]:mt-2 [&_p]:text-sm [&_p]:leading-relaxed [&_p]:text-muted-foreground">
        <p>
          This version of GymPerformance is in development and is not yet available
          to members. The privacy policy for the web version is being finalised and
          will be published here before the app is released.
        </p>

        <p>
          If you are a current GymPerformance member using the iOS app, the privacy
          policy that applies to you is available within that app.
        </p>
      </article>
    </AppShell>
  );
}