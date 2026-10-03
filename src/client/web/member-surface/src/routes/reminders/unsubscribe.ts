import { createFileRoute } from "@tanstack/react-router";
import { proxyUnsubscribe } from "@/lib/gp/unsubscribe-proxy";

export const Route = createFileRoute("/reminders/unsubscribe")({
  server: {
    handlers: {
      GET: async ({ request }) => proxyUnsubscribe(request),
      POST: async ({ request }) => proxyUnsubscribe(request),
    },
  },
});
