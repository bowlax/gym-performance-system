/**
 * Dev-only stub broker guard (web analog of iOS StubBrokerReleaseGuard).
 *
 * Production / preview builds must never mint via StubTeamUpBroker — that
 * path shares one TeamUp identity across callers.
 */
export function isStubBrokerAllowed(): boolean {
  // Vite replaces import.meta.env.DEV / PROD at build time.
  if (import.meta.env.PROD) return false;
  return import.meta.env.VITE_GYMPERF_USE_STUB_BROKER === "true";
}

export function assertStubBrokerAllowed(): void {
  if (!isStubBrokerAllowed()) {
    throw new Error(
      "StubTeamUpBroker is forbidden outside local DEV with VITE_GYMPERF_USE_STUB_BROKER=true. Use real TeamUp OAuth.",
    );
  }
}
