import { createFileRoute } from "@tanstack/react-router";
import { confirmKioskToken } from "@/lib/gp/kiosk-upstream.server";

function html(status: number, message: string): Response {
  return new Response(
    `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>GymPerformance</title></head><body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;padding:24px;"><p>${message}</p></body></html>`,
    {
      status,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  );
}

export const Route = createFileRoute("/kiosk/confirm")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const token = new URL(request.url).searchParams.get("token") ?? "";
        if (!token) return html(404, "This confirmation link is not valid.");
        let upstream: Response;
        try {
          upstream = await confirmKioskToken(token);
        } catch {
          return html(502, "Could not confirm that session. Try the link again.");
        }
        if (upstream.ok) {
          return new Response(null, {
            status: 302,
            headers: { Location: "/kiosk/logged", "Cache-Control": "no-store" },
          });
        }
        if (upstream.status === 404) {
          return html(404, "This confirmation link has already been used or is not valid.");
        }
        return html(upstream.status, "Could not confirm that session.");
      },
    },
  },
});
