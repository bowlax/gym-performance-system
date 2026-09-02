import { handleOwnerFetch, handleOwnerScheduled, type OwnerApiEnv } from "./owner-api-handlers";

export default {
  async fetch(request: Request, env: OwnerApiEnv): Promise<Response> {
    return handleOwnerFetch(request, env);
  },
  async scheduled(
    _controller: ScheduledController,
    env: OwnerApiEnv,
    ctx: ExecutionContext,
  ): Promise<void> {
    ctx.waitUntil(handleOwnerScheduled(env));
  },
};
