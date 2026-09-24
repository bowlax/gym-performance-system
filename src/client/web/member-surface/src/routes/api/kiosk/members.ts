import { createFileRoute } from "@tanstack/react-router";
import { proxyKioskFunction } from "@/lib/gp/kiosk-upstream.server";

export const Route = createFileRoute("/api/kiosk/members")({
  server: {
    handlers: {
      GET: async () => proxyKioskFunction({ action: "members" }),
    },
  },
});
