/**
 * HTTP-level tests for owner-member-names.
 *
 * Routing tests always run against handleOwnerMemberNamesRequest.
 * Live RLS: member JWT is 403; owner JWT (member_id not in members) lists names.
 */
import { assertEquals } from "jsr:@std/assert@1";
import { SignJWT } from "jsr:@panva/jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleOwnerMemberNamesRequest } from "./handler.ts";

const ENDPOINT = "http://localhost/functions/v1/owner-member-names";

Deno.test("HTTP GET owner-member-names returns 405 via the served handler", async () => {
  const res = await handleOwnerMemberNamesRequest(
    new Request(ENDPOINT, { method: "GET" }),
  );
  assertEquals(res.status, 405);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Method not allowed");
});

Deno.test("HTTP POST owner-member-names without Authorization returns 401", async () => {
  const res = await handleOwnerMemberNamesRequest(
    new Request(ENDPOINT, { method: "POST" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json() as { error?: string };
  assertEquals(body.error, "Unauthorized");
});

Deno.test("HTTP OPTIONS owner-member-names returns 200 via the served handler", async () => {
  const res = await handleOwnerMemberNamesRequest(
    new Request(ENDPOINT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

interface LiveEnv {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
  jwtSecret: string;
}

function liveEnv(): LiveEnv | null {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const jwtSecret = Deno.env.get("JWT_SIGNING_SECRET");
  if (!url || !anonKey || !serviceRoleKey || !jwtSecret) {
    return null;
  }
  return { url, anonKey, serviceRoleKey, jwtSecret };
}

async function mintJwt(
  secret: string,
  claims: { memberId: string; gymId: string; appRole: "member" | "coach" | "owner" },
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({
    sub: claims.memberId,
    role: "authenticated",
    app_role: claims.appRole,
    member_id: claims.memberId,
    gym_id: claims.gymId,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer("supabase")
    .setAudience("authenticated")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(new TextEncoder().encode(secret));
}

function postWithToken(token: string, body: unknown = {}): Request {
  return new Request(ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

Deno.test({
  name: "HTTP POST member JWT is refused; owner JWT lists display_name without a members row for the caller",
  ignore: liveEnv() == null,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const env = liveEnv();
    if (!env) throw new Error("live env disappeared");

    const originalGet = Deno.env.get.bind(Deno.env);
    Deno.env.get = (name: string) => {
      if (name === "SUPABASE_URL") return env.url;
      if (name === "SUPABASE_ANON_KEY") return env.anonKey;
      if (name === "SUPABASE_PUBLISHABLE_KEY") return env.anonKey;
      if (name === "SERVICE_ROLE_KEY") return env.serviceRoleKey;
      if (name === "JWT_SIGNING_SECRET") return env.jwtSecret;
      return originalGet(name);
    };

    const admin = createClient(env.url, env.serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const gymId = crypto.randomUUID();
    const memberA = crypto.randomUUID();
    const memberB = crypto.randomUUID();
    const memberCaller = crypto.randomUUID();
    const ownerCaller = crypto.randomUUID();
    const providerId = `owner-names-test-${gymId.slice(0, 8)}`;

    try {
      const gymInsert = await admin.from("gyms").insert({
        id: gymId,
        teamup_provider_id: providerId,
        name: "Owner Names Test Gym",
      });
      if (gymInsert.error) throw gymInsert.error;

      const membersInsert = await admin.from("members").insert([
        {
          id: memberA,
          gym_id: gymId,
          teamup_customer_id: "NAME-A",
          display_name: "Ada Example",
        },
        {
          id: memberB,
          gym_id: gymId,
          teamup_customer_id: "NAME-B",
          display_name: "Ben Example",
        },
        {
          id: memberCaller,
          gym_id: gymId,
          teamup_customer_id: "NAME-CALLER",
          display_name: "Member Caller",
        },
      ]);
      if (membersInsert.error) throw membersInsert.error;

      const memberToken = await mintJwt(env.jwtSecret, {
        memberId: memberCaller,
        gymId,
        appRole: "member",
      });
      const ownerToken = await mintJwt(env.jwtSecret, {
        memberId: ownerCaller,
        gymId,
        appRole: "owner",
      });

      const memberRes = await handleOwnerMemberNamesRequest(
        postWithToken(memberToken),
      );
      assertEquals(memberRes.status, 403);
      const memberBody = await memberRes.json() as { error?: string; members?: unknown };
      assertEquals(memberBody.error, "Forbidden");
      assertEquals(memberBody.members, undefined);

      const ownerRes = await handleOwnerMemberNamesRequest(
        postWithToken(ownerToken),
      );
      assertEquals(ownerRes.status, 200);
      const ownerBody = await ownerRes.json() as {
        members: Array<{
          member_id: string;
          teamup_customer_id: string | null;
          display_name: string;
        }>;
      };
      assertEquals(ownerBody.members.length, 3);
      const byId = new Map(ownerBody.members.map((row) => [row.member_id, row]));
      assertEquals(byId.get(memberA)?.display_name, "Ada Example");
      assertEquals(byId.get(memberB)?.display_name, "Ben Example");
      assertEquals(byId.has(ownerCaller), false);

      const leaked = JSON.stringify(ownerBody);
      assertEquals(leaked.includes("Bearer"), false);
    } finally {
      await admin.from("members").delete().eq("gym_id", gymId);
      await admin.from("owner_surface_grants").delete().eq("gym_id", gymId);
      await admin.from("gyms").delete().eq("id", gymId);
      Deno.env.get = originalGet;
    }
  },
});
