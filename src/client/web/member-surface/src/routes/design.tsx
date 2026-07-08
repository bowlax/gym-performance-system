import { createFileRoute } from "@tanstack/react-router";
import { Button } from "@/components/ui/button";
import { PBCard } from "@/components/gp/pb-card";
import { FormField } from "@/components/gp/form-field";

export const Route = createFileRoute("/design")({
  head: () => ({
    meta: [
      { title: "GymPerformance — Design System" },
      {
        name: "description",
        content:
          "Design tokens, typography and core components for the GymPerformance member web experience.",
      },
      { property: "og:title", content: "GymPerformance — Design System" },
      {
        property: "og:description",
        content:
          "Shared visual language for the GymPerformance web member surface.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: DesignSystem,
});

const swatches: Array<{ name: string; token: string; value: string; className: string }> = [
  { name: "Wolf blue", token: "--primary", value: "#1A5BA6", className: "bg-primary" },
  { name: "Wolf blue 30% (disabled)", token: "--primary-disabled", value: "#1A5BA6 @ 30%", className: "bg-primary-disabled" },
  { name: "Wolf blue 50% (chart)", token: "--primary-chart-muted", value: "#1A5BA6 @ 50%", className: "bg-primary-chart-muted" },
  { name: "PB yellow", token: "--pb", value: "#FFD600", className: "bg-pb" },
  { name: "PB fill 15%", token: "--pb-fill", value: "#FFD600 @ 15%", className: "bg-pb-fill" },
  { name: "PB badge 25%", token: "--pb-badge", value: "#FFD600 @ 25%", className: "bg-pb-badge" },
  { name: "Background", token: "--background", value: "#FFFFFF / #000000", className: "bg-background border border-border" },
  { name: "Card", token: "--card", value: "#F2F2F7 / #1C1C1E", className: "bg-card border border-border" },
  { name: "Input surface", token: "--surface", value: "#FFFFFF / #2C2C2E", className: "bg-surface border border-border" },
  { name: "Primary text", token: "--foreground", value: "#000000 / #FFFFFF", className: "bg-foreground" },
  { name: "Secondary text", token: "--muted-foreground", value: "rgba(60,60,67,.6)", className: "bg-muted-foreground" },
];

function DesignSystem() {
  return (
    <main className="min-h-screen bg-background">
      <div className="mx-auto max-w-5xl px-6 py-14">
        <header className="mb-12">
          <div className="flex items-center gap-2 text-sm font-medium text-primary">
            <span className="inline-block size-2 rounded-full bg-primary" />
            GymPerformance · Web
          </div>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight text-foreground">
            Design system
          </h1>
          <p className="mt-3 max-w-2xl text-base text-muted-foreground">
            Wolf blue leads. Electric yellow celebrates personal bests as an
            accent — never a fill. Typography, radii, and spacing mirror the
            iOS app so members feel one product across surfaces.
          </p>
        </header>

        <Section title="Colour" caption="Semantic tokens, light mode shown">
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            {swatches.map((s) => (
              <div
                key={s.token}
                className="rounded-2xl border border-border bg-surface p-3"
              >
                <div className={`h-16 w-full rounded-xl ${s.className}`} />
                <div className="mt-3 text-sm font-medium text-foreground">
                  {s.name}
                </div>
                <div className="mt-0.5 font-numeric text-xs text-muted-foreground">
                  {s.token} · {s.value}
                </div>
              </div>
            ))}
          </div>
        </Section>

        <Section title="Typography" caption="SF Pro system stack, tabular numerics for weights">
          <div className="space-y-6 rounded-2xl border border-border bg-surface p-6">
            <div>
              <div className="text-xs uppercase tracking-wider text-muted-foreground">
                Display · numeric
              </div>
              <div className="mt-1 font-numeric text-7xl font-semibold leading-none text-foreground">
                142.5
                <span className="ml-2 text-3xl font-medium text-muted-foreground">
                  kg
                </span>
              </div>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <div className="text-xs uppercase tracking-wider text-muted-foreground">
                  Heading
                </div>
                <div className="mt-1 text-2xl font-semibold tracking-tight text-foreground">
                  Log tonight's session
                </div>
              </div>
              <div>
                <div className="text-xs uppercase tracking-wider text-muted-foreground">
                  Body
                </div>
                <div className="mt-1 text-base text-foreground">
                  Every rep counts toward your next PB.
                </div>
              </div>
              <div>
                <div className="text-xs uppercase tracking-wider text-muted-foreground">
                  Label
                </div>
                <div className="mt-1 text-sm font-medium text-muted-foreground">
                  Back squat · Working set
                </div>
              </div>
              <div>
                <div className="text-xs uppercase tracking-wider text-muted-foreground">
                  Caption
                </div>
                <div className="mt-1 text-xs text-muted-foreground">
                  Last updated 2 hours ago
                </div>
              </div>
            </div>
          </div>
        </Section>

        <Section title="PB card" caption="Yellow ring + badge celebrates a personal best">
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            <PBCard
              lift="Back squat"
              value={142.5}
              achievedAt="Set on 2 Jul 2026"
              isPB
            />
            <PBCard
              lift="Bench press"
              value={97.5}
              achievedAt="Set on 18 Jun 2026"
            />
            <PBCard
              lift="Deadlift"
              value={185}
              achievedAt="Set on 24 Jun 2026"
            />
          </div>
        </Section>

        <Section title="Buttons" caption="Primary is full-width, 16px radius, disabled = wolf blue 30%">
          <div className="flex flex-col gap-3 rounded-[16px] bg-card p-4">
            <Button>Log set</Button>
            <Button disabled>Log set (disabled)</Button>
            <Button variant="pb">PB celebration</Button>
            <div className="flex flex-wrap items-center gap-3">
              <Button variant="outline" className="w-auto">Cancel</Button>
              <Button variant="ghost" className="w-auto">Skip</Button>
              <Button size="sm" variant="outline" className="w-auto">Edit</Button>
            </div>
          </div>
        </Section>

        <Section title="Form field" caption="Input surface with 10px radius, wolf-blue focus ring">
          <div className="grid gap-3 rounded-[16px] bg-card p-4 sm:grid-cols-2">
            <FormField
              label="Exercise"
              placeholder="Back squat"
              defaultValue="Back squat"
            />
            <FormField
              label="Working weight"
              numeric
              inputMode="decimal"
              defaultValue="142.5"
              trailing="kg"
              hint="Enter the top set for this exercise."
            />
            <FormField
              label="Reps"
              numeric
              inputMode="numeric"
              defaultValue="5"
            />
            <FormField
              label="RPE"
              numeric
              inputMode="decimal"
              defaultValue="8.5"
              hint="Rate of perceived exertion, 1–10."
            />
          </div>
        </Section>

        <footer className="mt-16 text-xs text-muted-foreground">
          Confirm the visual match, then we'll build out the Board, Log
          Session, and account screens on top of these tokens.
        </footer>
      </div>
    </main>
  );
}

function Section({
  title,
  caption,
  children,
}: {
  title: string;
  caption: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-6">
      <div className="mb-3 flex items-end justify-between gap-4">
        <h2 className="text-xs font-semibold uppercase tracking-[0.08em] text-muted-foreground">
          {title}
        </h2>
        <p className="text-xs text-muted-foreground">{caption}</p>
      </div>
      {children}
    </section>
  );
}