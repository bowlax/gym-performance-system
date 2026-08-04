import { createFileRoute } from "@tanstack/react-router";
import { handleOAuthCallback } from "@/lib/gp/auth-handlers";
import { writeAuthSession } from "@/lib/gp/session.server";

/**
 * Broker OAuth return target. Tokens arrive in the query string on this
 * server-to-server redirect hop, are sealed into an httpOnly cookie, then
 * the browser is sent to a clean `/` with no tokens in the URL.
 */
export const Route = createFileRoute("/auth/callback")({
  server: {
    handlers: {
      GET: async ({ request }) =>
        handleOAuthCallback(request, { write: writeAuthSession }),
    },
  },
});
