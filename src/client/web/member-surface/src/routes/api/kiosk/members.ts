import { createFileRoute } from "@tanstack/react-router";
import { listKioskMembers } from "@/lib/gp/kiosk-upstream.server";

export const Route = createFileRoute("/api/kiosk/members")({
  server: {
    handlers: {
      GET: async () => listKioskMembers(),
    },
  },
});
