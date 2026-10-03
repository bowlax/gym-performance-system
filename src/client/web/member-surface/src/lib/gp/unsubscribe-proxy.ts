import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "@/lib/gp/env";

/**
 * Supabase Edge Functions rewrite GET `text/html` responses to `text/plain`
 * on shared project domains (HTML hosting is only allowed with a custom
 * domain). The member-web Worker is the public unsubscribe landing host, so
 * it must force `text/html` for GET regardless of the upstream Content-Type.
 */
export const UNSUBSCRIBE_HTML_CONTENT_TYPE = "text/html; charset=utf-8";

export function unsubscribeUpstreamUrl(
  token: string,
  supabaseUrl: string = SUPABASE_URL,
): string {
  const target = new URL(
    "functions/v1/log-reminders/unsubscribe",
    supabaseUrl.endsWith("/") ? supabaseUrl : `${supabaseUrl}/`,
  );
  target.searchParams.set("token", token);
  return target.toString();
}

export function unsubscribeResponseContentType(
  method: string,
  upstreamContentType: string | null,
): string {
  if (method === "GET") {
    return UNSUBSCRIBE_HTML_CONTENT_TYPE;
  }
  return upstreamContentType ?? "application/json";
}

export type ProxyUnsubscribeOptions = {
  fetchImpl?: typeof fetch;
  supabaseUrl?: string;
  supabasePublishableKey?: string;
};

export async function proxyUnsubscribe(
  request: Request,
  options: ProxyUnsubscribeOptions = {},
): Promise<Response> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const supabaseUrl = options.supabaseUrl ?? SUPABASE_URL;
  const supabasePublishableKey =
    options.supabasePublishableKey ?? SUPABASE_PUBLISHABLE_KEY;
  const token = new URL(request.url).searchParams.get("token") ?? "";
  const upstream = await fetchImpl(unsubscribeUpstreamUrl(token, supabaseUrl), {
    method: request.method,
    headers: {
      apikey: supabasePublishableKey,
      "Content-Type": request.headers.get("Content-Type") ??
        "application/x-www-form-urlencoded",
    },
    body: request.method === "POST" ? await request.text() : undefined,
    redirect: "manual",
  });

  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: {
      "Content-Type": unsubscribeResponseContentType(
        request.method,
        upstream.headers.get("Content-Type"),
      ),
      "Cache-Control": "no-store",
    },
  });
}
