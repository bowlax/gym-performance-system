/**
 * Edge Function entry — Deno.serve only.
 * Request handling lives in handler.ts so HTTP-level tests can import the
 * router without starting a server on module load.
 */
import { handleAddExercisesToSessionRequest } from "./handler.ts";

Deno.serve(handleAddExercisesToSessionRequest);
