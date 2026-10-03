import { createFileRoute } from "@tanstack/react-router";
import { createServerFn } from "@tanstack/react-start";
import { UnsubscribeConfirmation } from "@/components/gp/unsubscribe-confirmation";
import {
  performUnsubscribe,
  proxyUnsubscribePost,
  type UnsubscribeResult,
} from "@/lib/gp/unsubscribe-proxy";

const runUnsubscribe = createServerFn({ method: "GET" })
  .validator((token: string) => token)
  .handler(async ({ data: token }): Promise<UnsubscribeResult> => {
    return performUnsubscribe(token);
  });

export const Route = createFileRoute("/reminders/unsubscribe")({
  validateSearch: (search: Record<string, unknown>) => ({
    token: typeof search.token === "string" ? search.token : "",
  }),
  loaderDeps: ({ search: { token } }) => ({ token }),
  loader: async ({ deps: { token } }) => runUnsubscribe({ data: token }),
  head: () => ({
    meta: [
      { title: "Email reminders — GymPerformance" },
      {
        name: "description",
        content: "Update your GymPerformance session reminder email preferences.",
      },
    ],
  }),
  component: UnsubscribeScreen,
  server: {
    handlers: {
      // Gmail List-Unsubscribe one-click (no browser UI).
      POST: async ({ request }) => proxyUnsubscribePost(request),
    },
  },
});

function UnsubscribeScreen() {
  const result = Route.useLoaderData();
  return <UnsubscribeConfirmation result={result} />;
}
