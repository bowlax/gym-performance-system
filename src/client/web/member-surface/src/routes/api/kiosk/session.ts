import { createFileRoute } from "@tanstack/react-router";
import { KioskLoginError, signInOwnerWithPassword } from "@/lib/gp/kiosk-password";
import {
  readFreshKioskSession,
  writeKioskSession,
} from "@/lib/gp/kiosk-session.server";
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "@/lib/gp/env";

const NO_STORE = { "Cache-Control": "private, no-store" };

export const Route = createFileRoute("/api/kiosk/session")({
  server: {
    handlers: {
      GET: async () => {
        const session = await readFreshKioskSession();
        if (!session) {
          return Response.json(
            { error: "Unauthorized" },
            { status: 401, headers: NO_STORE },
          );
        }
        return Response.json({ authenticated: true }, { headers: NO_STORE });
      },
      POST: async ({ request }) => {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return Response.json(
            { error: "Invalid JSON body" },
            { status: 400, headers: NO_STORE },
          );
        }
        const record = typeof body === "object" && body !== null
          ? body as { email?: unknown; password?: unknown }
          : {};
        const email = typeof record.email === "string" ? record.email : "";
        const password = typeof record.password === "string" ? record.password : "";
        if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
          return Response.json(
            { error: "Supabase public config missing on server" },
            { status: 503, headers: NO_STORE },
          );
        }
        try {
          const session = await signInOwnerWithPassword({
            email,
            password,
            supabaseUrl: SUPABASE_URL,
            publishableKey: SUPABASE_PUBLISHABLE_KEY,
          });
          await writeKioskSession(session);
          return Response.json({ authenticated: true }, { headers: NO_STORE });
        } catch (error) {
          if (error instanceof KioskLoginError) {
            return Response.json(
              { error: error.message },
              { status: error.status, headers: NO_STORE },
            );
          }
          return Response.json(
            { error: "Could not sign in." },
            { status: 502, headers: NO_STORE },
          );
        }
      },
    },
  },
});
