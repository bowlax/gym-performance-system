// @lovable.dev/vite-tanstack-config already includes the following — do NOT add them manually
// or the app will break with duplicate plugins:
//   - tanstackStart, viteReact, tailwindcss, tsConfigPaths, nitro (build-only using cloudflare as a default target),
//     componentTagger (dev-only), VITE_* env injection, @ path alias, React/TanStack dedupe,
//     error logger plugins, and sandbox detection (port/host/strictPort).
// You can pass additional config via defineConfig({ vite: { ... }, etc... }) if needed.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

export default defineConfig({
  tanstackStart: {
    // Redirect TanStack Start's bundled server entry to src/server.ts (our SSR error wrapper).
    // nitro/vite builds from this
    server: { entry: "server" },
  },
  vite: {
    define: {
      // Expose selected server-side secrets to the browser bundle so we can
      // treat the Supabase publishable key and the stub test member id as
      // real environment variables rather than hardcoded strings. Only
      // publishable / non-sensitive values may be added here.
      "import.meta.env.VITE_GYMPERF_SUPABASE_URL": JSON.stringify(
        process.env.GYMPERF_SUPABASE_URL ?? "",
      ),
      "import.meta.env.VITE_GYMPERF_SUPABASE_PUBLISHABLE_KEY": JSON.stringify(
        process.env.GYMPERF_SUPABASE_PUBLISHABLE_KEY ?? "",
      ),
      "import.meta.env.VITE_GYMPERF_TEST_DEVICE_MEMBER_ID": JSON.stringify(
        process.env.TEST_DEVICE_MEMBER_ID ?? "",
      ),
    },
  },
});
