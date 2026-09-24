import { createFileRoute, Link } from "@tanstack/react-router";
import { AppShell } from "@/components/gp/app-shell";

export const Route = createFileRoute("/kiosk/logged")({
  head: () => ({
    meta: [
      { title: "Logged — GymPerformance" },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: KioskLoggedScreen,
});

function KioskLoggedScreen() {
  return (
    <AppShell>
      <div className="rounded-[16px] bg-card p-6">
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">
          Logged
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Your session is saved. If something needs changing, edit or delete
          it in the app.
        </p>
        <Link
          to="/"
          className="mt-5 inline-flex h-12 items-center justify-center rounded-[16px] bg-primary px-5 text-base font-semibold text-primary-foreground"
        >
          Go to your board
        </Link>
      </div>
    </AppShell>
  );
}
