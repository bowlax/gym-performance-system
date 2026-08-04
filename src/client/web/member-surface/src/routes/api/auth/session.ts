import { createFileRoute } from "@tanstack/react-router";
import { handleAuthSessionGet } from "@/lib/gp/auth-handlers";
import { refreshGoTrueSession } from "@/lib/gp/gotrue-refresh.server";
import {
  clearAuthSession,
  readAuthSession,
  writeAuthSession,
} from "@/lib/gp/session.server";
import {
  SUPABASE_PUBLISHABLE_KEY,
  SUPABASE_URL,
} from "@/lib/gp/env";

/**
 * Returns a current access token for the browser Supabase client.
 * Never returns refresh_token to client JS.
 */
export const Route = createFileRoute("/api/auth/session")({
  server: {
    handlers: {
      GET: async () =>
        handleAuthSessionGet({
          store: {
            read: readAuthSession,
            write: writeAuthSession,
            clear: clearAuthSession,
          },
          refresh: async (refreshToken) => {
            if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
              throw new Error("Supabase public config missing on server");
            }
            return refreshGoTrueSession({
              refreshToken,
              supabaseUrl: SUPABASE_URL,
              publishableKey: SUPABASE_PUBLISHABLE_KEY,
            });
          },
        }),
    },
  },
});
