import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "./env";

/**
 * Build a supabase-js client that always sends the broker JWT as the
 * bearer token, so RLS sees the member identity encoded in the JWT.
 *
 * We disable Supabase's own auth session handling — the broker owns
 * identity. Each set operation re-creates the client so PostgREST calls
 * carry the fresh Authorization header.
 */
export function createGymPerfClient(token: string): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  });
}