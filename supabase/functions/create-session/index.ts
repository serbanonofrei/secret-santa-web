// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

import { generateInviteCode, generateOrganizerToken, pickRandom } from "./random.ts";
import { type CreateSessionInput, type FieldError, validateCreateSessionInput } from "./validation.ts";

// =============================================================================
// Types
// =============================================================================

interface SelectedColor {
  catalogId: number;
  name: string;
  hexColor: string;
}

interface CreateSessionResponse {
  sessionId: string;
  inviteCode: string;
  organizerToken: string;
  published: false;
  selectedColors: SelectedColor[];
}

/** Shape returned by public.create_session_with_colors(...) */
interface CreateSessionRpcResult {
  sessionId: string;
  selectedColors: SelectedColor[];
}

interface ErrorBody {
  error: {
    code: string;
    message: string;
    details?: FieldError[] | Record<string, unknown>;
  };
}

/** Minimal structural type of a PostgREST error (avoids a direct supabase-js import). */
interface PostgrestErrorLike {
  code: string;
  message: string;
  details: string | null;
  hint: string | null;
}

type RpcResponse = {
  data: unknown;
  error: PostgrestErrorLike | null;
};

// =============================================================================
// Constants
// =============================================================================

/** Retries on unique violations (invite_code / organizer_token collisions). */
const MAX_INSERT_ATTEMPTS = 5;

/** Custom SQLSTATEs raised by public.create_session_with_colors */
const PG_UNIQUE_VIOLATION = "23505";
const PG_FOREIGN_KEY_VIOLATION = "23503";
const PG_UNKNOWN_COLOR = "SC001";
const PG_INVALID_ARGUMENT = "SC002";
const PGRST_FUNCTION_NOT_FOUND = "PGRST202";

// =============================================================================
// Helpers
// =============================================================================

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: ErrorBody["error"]["details"],
  ) {
    super(message);
    this.name = "HttpError";
  }
}

function jsonResponse<T>(body: T, status: number): Response {
  return Response.json(body, { status });
}

function errorResponse(err: HttpError): Response {
  const body: ErrorBody = {
    error: {
      code: err.code,
      message: err.message,
      ...(err.details !== undefined ? { details: err.details } : {}),
    },
  };
  return jsonResponse(body, err.status);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isSelectedColor(value: unknown): value is SelectedColor {
  return (
    isRecord(value) &&
    typeof value.catalogId === "number" &&
    typeof value.name === "string" &&
    typeof value.hexColor === "string"
  );
}

function isCreateSessionRpcResult(value: unknown): value is CreateSessionRpcResult {
  return (
    isRecord(value) &&
    typeof value.sessionId === "string" &&
    Array.isArray(value.selectedColors) &&
    value.selectedColors.every(isSelectedColor)
  );
}

async function readJsonBody(req: Request): Promise<unknown> {
  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new HttpError(415, "UNSUPPORTED_MEDIA_TYPE", "Content-Type must be application/json");
  }

  try {
    return await req.json();
  } catch {
    throw new HttpError(400, "INVALID_JSON", "Request body is not valid JSON");
  }
}

/** Maps a database error from the RPC to an HttpError. */
function mapDatabaseError(error: PostgrestErrorLike): HttpError {
  switch (error.code) {
    case PG_UNKNOWN_COLOR: {
      const unknownIds = (error.details ?? "")
        .split(",")
        .map((id) => Number(id.trim()))
        .filter((id) => Number.isInteger(id));
      return new HttpError(422, "UNKNOWN_COLORS", "One or more allowedColors do not exist in the color catalog or are disabled", {
        unknownColorIds: unknownIds,
      });
    }
    case PG_INVALID_ARGUMENT:
      return new HttpError(422, "VALIDATION_ERROR", error.message);
    case PG_FOREIGN_KEY_VIOLATION:
      return new HttpError(422, "INVALID_REFERENCE", "A referenced record does not exist");
    case PGRST_FUNCTION_NOT_FOUND:
      console.error("[create-session] RPC create_session_with_colors not found. Did you apply the migration?", error);
      return new HttpError(500, "SERVER_MISCONFIGURED", "Session service is not configured correctly");
    default:
      console.error("[create-session] Unexpected database error", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to create session");
  }
}

// =============================================================================
// Core logic
// =============================================================================

type AdminClient = {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<RpcResponse>;
};

async function createSession(admin: AdminClient, input: CreateSessionInput): Promise<CreateSessionResponse> {
  // Step 6: random selection happens once; it is independent of the invite code retries.
  const selectedColorIds = pickRandom(input.allowedColors, input.maxParticipants);

  for (let attempt = 1; attempt <= MAX_INSERT_ATTEMPTS; attempt++) {
    // Steps 1 + 2
    const organizerToken = generateOrganizerToken();
    const inviteCode = generateInviteCode();

    // Steps 3, 4, 5 and 7 run inside ONE Postgres transaction (the RPC function body).
    // target_color_id stays NULL and assigned = false. No Secret Santa chain yet.
    const { data, error } = await admin.rpc("create_session_with_colors", {
      p_session_name: input.sessionName,
      p_invite_code: inviteCode,
      p_max_participants: input.maxParticipants,
      p_organizer_token: organizerToken,
      p_allowed_color_ids: input.allowedColors,
      p_selected_color_ids: selectedColorIds,
    });

    if (error) {
      if (error.code === PG_UNIQUE_VIOLATION && attempt < MAX_INSERT_ATTEMPTS) {
        console.warn(`[create-session] Unique collision on attempt ${attempt}, retrying`, error.message);
        continue;
      }
      if (error.code === PG_UNIQUE_VIOLATION) {
        console.error("[create-session] Exhausted retries on unique collisions", error);
        throw new HttpError(503, "INVITE_CODE_EXHAUSTED", "Could not generate a unique invite code, please retry");
      }
      throw mapDatabaseError(error);
    }

    if (!isCreateSessionRpcResult(data)) {
      console.error("[create-session] Unexpected RPC result shape", data);
      throw new HttpError(500, "INVALID_DB_RESPONSE", "Unexpected response from database");
    }

    return {
      sessionId: data.sessionId,
      inviteCode,
      organizerToken,
      published: false,
      selectedColors: data.selectedColors,
    };
  }

  // Unreachable: the loop either returns or throws.
  throw new HttpError(500, "INTERNAL_ERROR", "Failed to create session");
}

// =============================================================================
// Handler
// =============================================================================

// 'publishable': client-facing (Flutter app), 'secret': server-to-server.
// All writes go through ctx.supabaseAdmin (service role, bypasses RLS).
export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    try {
      if (req.method !== "POST") {
        throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST is supported");
      }

      const body = await readJsonBody(req);

      const validation = validateCreateSessionInput(body);
      if (!validation.ok) {
        throw new HttpError(422, "VALIDATION_ERROR", "Request validation failed", validation.errors);
      }

      const result = await createSession(ctx.supabaseAdmin as unknown as AdminClient, validation.value);
      return jsonResponse<CreateSessionResponse>(result, 201);
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err);
      }
      console.error("[create-session] Unhandled error", err);
      return errorResponse(new HttpError(500, "INTERNAL_ERROR", "Internal server error"));
    }
  }),
};

/* To invoke locally:

  1. supabase start && supabase db reset   (applies the migration)
  2. supabase functions serve create-session
  3. curl -i --request POST 'http://127.0.0.1:54321/functions/v1/create-session' \
       --header 'apikey: <publishable key>' \
       --header 'Content-Type: application/json' \
       --data '{"sessionName":"Office Xmas 2026","maxParticipants":3,"allowedColors":[1,2,3,4,5]}'

  Status codes:
    201 created | 400 invalid JSON | 405 wrong method | 415 wrong content type
    422 validation / unknown colors | 503 invite code collisions exhausted | 500 server error
*/
