import { createFileRoute } from "@tanstack/react-router";
import { proxyKioskExercises } from "@/lib/gp/kiosk-upstream.server";

export const Route = createFileRoute("/api/kiosk/exercises")({
  server: {
    handlers: {
      GET: async () => proxyKioskExercises(),
    },
  },
});
