import { createFileRoute } from "@tanstack/react-router";
import { serveLandingPage } from "@/lib/gp/landing-page";

/**
 * Explanation page for members (iPhone + web entry).
 * Served from the Worker bundle so deploys that drop `public/landing/index.html`
 * still return the HTML instead of the SPA 404 shell.
 */
export const Route = createFileRoute("/landing")({
  server: {
    handlers: {
      GET: async ({ request }) =>
        serveLandingPage(request) ??
        new Response("Not found", { status: 404 }),
      HEAD: async ({ request }) =>
        serveLandingPage(request) ??
        new Response(null, { status: 404 }),
    },
  },
});
