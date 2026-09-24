import { useEffect, useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Button } from "@/components/ui/button";
import { FormField } from "@/components/gp/form-field";
import { KioskShell } from "@/components/gp/kiosk-shell";

export const Route = createFileRoute("/kiosk/")({
  head: () => ({
    meta: [
      { title: "Gym kiosk — GymPerformance" },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: KioskHome,
});

interface KioskMember {
  member_id: string;
  display_name: string;
}

function KioskHome() {
  const [status, setStatus] = useState<"checking" | "signed_out" | "ready">("checking");

  useEffect(() => {
    let cancelled = false;
    void fetch("/api/kiosk/session").then((res) => {
      if (cancelled) return;
      setStatus(res.ok ? "ready" : "signed_out");
    }).catch(() => {
      if (!cancelled) setStatus("signed_out");
    });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <KioskShell>
      {status === "checking" ? (
        <p className="text-sm text-muted-foreground">Checking session…</p>
      ) : status === "signed_out" ? (
        <KioskLogin onSignedIn={() => setStatus("ready")} />
      ) : (
        <KioskPicker />
      )}
    </KioskShell>
  );
}

function KioskLogin({ onSignedIn }: { onSignedIn: () => void }) {
  const [username, setUsername] = useState("");
  const [key, setKey] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch("/api/kiosk/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, key }),
      });
      const body = await res.json().catch(() => ({})) as { error?: string };
      if (!res.ok) {
        throw new Error(body.error ?? "Could not sign in.");
      }
      onSignedIn();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not sign in.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">
          Set up this kiosk
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Lee or Steve sign in once. It stays signed in for the next member.
        </p>
      </div>
      <div className="rounded-[16px] bg-card p-4 space-y-3">
        <FormField
          label="Username"
          type="text"
          autoComplete="username"
          value={username}
          onChange={(event) => setUsername(event.target.value)}
        />
        <FormField
          label="Key"
          type="password"
          autoComplete="current-password"
          value={key}
          onChange={(event) => setKey(event.target.value)}
        />
      </div>
      {error && (
        <p className="text-sm text-destructive">{error}</p>
      )}
      <Button type="submit" disabled={submitting}>
        {submitting ? "Signing in…" : "Sign in"}
      </Button>
    </form>
  );
}

function KioskPicker() {
  const navigate = useNavigate();
  const [members, setMembers] = useState<KioskMember[]>([]);
  const [memberId, setMemberId] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void fetch("/api/kiosk/members")
      .then(async (res) => {
        const body = await res.json().catch(() => ({})) as {
          error?: string;
          message?: string;
          members?: KioskMember[];
        };
        if (!res.ok) {
          throw new Error(body.error ?? body.message ?? "Could not load members.");
        }
        if (cancelled) return;
        const rows = body.members ?? [];
        setMembers(rows);
        setMemberId(rows[0]?.member_id ?? "");
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Could not load members.");
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const selected = members.find((member) => member.member_id === memberId);

  return (
    <form
      className="space-y-6"
      onSubmit={(event) => {
        event.preventDefault();
        if (!selected) return;
        void navigate({
          to: "/kiosk/log",
          search: { member: selected.member_id, name: selected.display_name },
        });
      }}
    >
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">
          Who trained?
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Pick your name, log the best set, then the next person can go.
        </p>
      </div>
      <div className="rounded-[16px] bg-card p-4">
        <label
          htmlFor="kiosk-member"
          className="text-sm font-medium text-foreground"
        >
          Name
        </label>
        {loading ? (
          <p className="mt-3 text-sm text-muted-foreground">Loading names…</p>
        ) : error ? (
          <p className="mt-3 text-sm text-destructive">{error}</p>
        ) : members.length === 0 ? (
          <p className="mt-3 text-sm text-muted-foreground">
            No members with a resolved name yet.
          </p>
        ) : (
          <select
            id="kiosk-member"
            value={memberId}
            onChange={(event) => setMemberId(event.target.value)}
            className="mt-2 h-14 w-full rounded-[10px] border border-input bg-surface px-3.5 text-lg text-foreground outline-none focus:border-primary focus:ring-4 focus:ring-primary/15"
          >
            {members.map((member) => (
              <option key={member.member_id} value={member.member_id}>
                {member.display_name}
              </option>
            ))}
          </select>
        )}
      </div>
      <Button type="submit" disabled={!selected}>
        Continue
      </Button>
    </form>
  );
}
