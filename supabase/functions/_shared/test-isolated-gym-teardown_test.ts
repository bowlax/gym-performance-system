import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  isLoopbackSupabaseUrl,
  onlyIfLoopback,
  throwIfPostgrestError,
} from "./test-isolated-gym-teardown.ts";

Deno.test("isLoopbackSupabaseUrl accepts local supabase API URLs", () => {
  assertEquals(isLoopbackSupabaseUrl("http://127.0.0.1:54321"), true);
  assertEquals(isLoopbackSupabaseUrl("http://localhost:54321"), true);
  assertEquals(isLoopbackSupabaseUrl("http://[::1]:54321"), true);
});

Deno.test("isLoopbackSupabaseUrl rejects hosted project URLs", () => {
  assertEquals(
    isLoopbackSupabaseUrl("https://ivrsxhuktebvypgtfoww.supabase.co"),
    false,
  );
  assertEquals(isLoopbackSupabaseUrl("not a url"), false);
});

Deno.test("onlyIfLoopback drops hosted mutating targets", () => {
  assertEquals(
    onlyIfLoopback({ url: "https://ivrsxhuktebvypgtfoww.supabase.co" }),
    null,
  );
  assertEquals(
    onlyIfLoopback({ url: "http://127.0.0.1:54321", key: "x" }),
    { url: "http://127.0.0.1:54321", key: "x" },
  );
});

Deno.test("throwIfPostgrestError is a no-op when delete/update succeeded", () => {
  throwIfPostgrestError("tombstone gyms", null);
});

Deno.test("throwIfPostgrestError fails loudly on a silent-403-shaped error", () => {
  assertThrows(
    () =>
      throwIfPostgrestError("DELETE gyms", {
        code: "42501",
        message: "permission denied for table gyms",
      }),
    Error,
    "DELETE gyms failed: [42501] permission denied for table gyms",
  );
});
