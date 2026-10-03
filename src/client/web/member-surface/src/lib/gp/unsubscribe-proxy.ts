import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "@/lib/gp/env";

export type UnsubscribeResult = {
  ok: boolean;
  status: number;
  message: string;
};

export type UnsubscribeFetchOptions = {
  fetchImpl?: typeof fetch;
  supabaseUrl?: string;
  supabasePublishableKey?: string;
};

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

/** Prefer known status copy; fall back to the Edge Function HTML body. */
export function unsubscribeMessageForResponse(
  status: number,
  body: string,
): string {
  if (status === 200) {
    return "You are unsubscribed from session reminder emails. You can turn them back on in Settings.";
  }
  if (status === 400) {
    return "This unsubscribe link is invalid or has expired.";
  }
  if (status === 503) {
    return "Unsubscribe is not configured.";
  }
  const fromHtml = body.match(/<p>(.*?)<\/p>/i)?.[1]?.trim();
  if (fromHtml) return fromHtml;
  return "Something went wrong while updating your reminder preferences.";
}

export async function performUnsubscribe(
  token: string,
  options: UnsubscribeFetchOptions = {},
): Promise<UnsubscribeResult> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const supabaseUrl = options.supabaseUrl ?? SUPABASE_URL;
  const supabasePublishableKey =
    options.supabasePublishableKey ?? SUPABASE_PUBLISHABLE_KEY;

  const upstream = await fetchImpl(unsubscribeUpstreamUrl(token, supabaseUrl), {
    method: "GET",
    headers: { apikey: supabasePublishableKey },
    redirect: "manual",
  });
  const body = await upstream.text();
  return {
    ok: upstream.ok,
    status: upstream.status,
    message: unsubscribeMessageForResponse(upstream.status, body),
  };
}

/** Gmail one-click POST — proxy JSON through; browsers use the GET landing page. */
export async function proxyUnsubscribePost(
  request: Request,
  options: UnsubscribeFetchOptions = {},
): Promise<Response> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const supabaseUrl = options.supabaseUrl ?? SUPABASE_URL;
  const supabasePublishableKey =
    options.supabasePublishableKey ?? SUPABASE_PUBLISHABLE_KEY;
  const token = new URL(request.url).searchParams.get("token") ?? "";

  const upstream = await fetchImpl(unsubscribeUpstreamUrl(token, supabaseUrl), {
    method: "POST",
    headers: {
      apikey: supabasePublishableKey,
      "Content-Type": request.headers.get("Content-Type") ??
        "application/x-www-form-urlencoded",
    },
    body: await request.text(),
    redirect: "manual",
  });

  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: {
      "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
      "Cache-Control": "no-store",
    },
  });
}
