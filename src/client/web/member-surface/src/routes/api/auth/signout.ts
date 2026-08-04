import { createFileRoute } from "@tanstack/react-router";
import { clearAuthSession } from "@/lib/gp/session.server";

export const Route = createFileRoute("/api/auth/signout")({
  server: {
    handlers: {
      POST: async () => {
        await clearAuthSession();
        return Response.json(
          { ok: true },
          { headers: { "Cache-Control": "private, no-store" } },
        );
      },
    },
  },
});
