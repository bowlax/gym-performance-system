// @lovable.dev/vite-tanstack-config already includes the following — do NOT add them manually
// or the app will break with duplicate plugins:
//   - tanstackStart, viteReact, tailwindcss, tsConfigPaths, nitro (build-only using cloudflare as a default target),
//     componentTagger (dev-only), VITE_* env injection, @ path alias, React/TanStack dedupe,
//     error logger plugins, and sandbox detection (port/host/strictPort).
// You can pass additional config via defineConfig({ vite: { ... }, etc... }) if needed.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";
import { loadEnv, type Plugin } from "vite";

/**
 * Injects GYMPERF_* values from .env / .env.local into the client bundle.
 *
 * `process.env` is not populated from Vite env files when this config module
 * is evaluated, and Lovable's built-in loadEnv only loads the `VITE_` prefix.
 * This plugin runs during config resolution (with the correct mode) and uses
 * loadEnv with an empty prefix so GYMPERF_* keys from .env.local are available.
 */
function gymPerfEnvDefinePlugin(): Plugin {
  return {
    name: "gymperf-env-define",
    config(_config, { mode }) {
      const env = loadEnv(mode, process.cwd(), "");
      return {
        define: {
          "import.meta.env.VITE_GYMPERF_SUPABASE_URL": JSON.stringify(
            env.GYMPERF_SUPABASE_URL ?? "",
          ),
          "import.meta.env.VITE_GYMPERF_SUPABASE_PUBLISHABLE_KEY": JSON.stringify(
            env.GYMPERF_SUPABASE_PUBLISHABLE_KEY ?? "",
          ),
          "import.meta.env.VITE_GYMPERF_TEST_DEVICE_MEMBER_ID": JSON.stringify(
            env.TEST_DEVICE_MEMBER_ID ?? "",
          ),
        },
      };
    },
  };
}

export default defineConfig({
  tanstackStart: {
    // Redirect TanStack Start's bundled server entry to src/server.ts (our SSR error wrapper).
    // nitro/vite builds from this
    server: { entry: "server" },
  },
  plugins: [gymPerfEnvDefinePlugin()],
});
