import { createFileRoute } from "@tanstack/react-router";
import { proxyKioskFunction } from "@/lib/gp/kiosk-upstream.server";

export const Route = createFileRoute("/api/kiosk/submit")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return Response.json(
            { error: "Invalid JSON body" },
            { status: 400, headers: { "Cache-Control": "private, no-store" } },
          );
        }
        const record = typeof body === "object" && body !== null
          ? body as Record<string, unknown>
          : {};
        return proxyKioskFunction({ ...record, action: "submit" });
      },
    },
  },
});
