// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

import { generateBrowserToken, generateParticipantId, generateRecoveryCode } from "./random.ts";
import { type FieldError, type JoinSessionInput, validateJoinSessionInput } from "./validation.ts";

// =============================================================================
// Types
// =============================================================================

interface ColorInfo {
  name: string;
  hexColor: string;
}

interface JoinSessionResponse {
  participantId: string;
  browserToken: string;
  recoveryCode: string;
  myColor: ColorInfo;
  giftColor: ColorInfo;
}

/** Shape returned by public.join_session(...) */
interface JoinSessionRpcResult {
  participantId: string;
  myColor: ColorInfo;
  giftColor: ColorInfo;
}

interface ErrorBody {
  error: {
    code: string;
    message: string;
    details?: FieldError[];
  };
}

/** Minimal structural type of a PostgREST error (avoids a direct supabase-js import). */
interface PostgrestErrorLike {
  code: string;
  message: string;
  details: string | null;
  hint: string | null;
}

interface RpcResponse {
  data: unknown;
  error: PostgrestErrorLike | null;
}

type AdminClient = {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<RpcResponse>;
};

// =============================================================================
// Constants
// =============================================================================

/** Retries on unique violations (participant id / browser token / recovery code collisions). */
const MAX_INSERT_ATTEMPTS = 5;

const PG_UNIQUE_VIOLATION = "23505";
/** Custom SQLSTATEs raised by public.join_session */
const PG_SESSION_NOT_FOUND = "SJ001";
const PG_SESSION_NOT_ACTIVE = "SJ002";
const PG_SESSION_FULL = "SJ003";
const PG_DUPLICATE_NAME = "SJ004";
const PG_INVALID_ARGUMENT = "SJ005";
const PGRST_FUNCTION_NOT_FOUND = "PGRST202";

// =============================================================================
// Helpers
// =============================================================================

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: FieldError[],
  ) {
    super(message);
    this.name = "HttpError";
  }
}

function errorResponse(err: HttpError): Response {
  const body: ErrorBody = {
    error: {
      code: err.code,
      message: err.message,
      ...(err.details !== undefined ? { details: err.details } : {}),
    },
  };
  return Response.json(body, { status: err.status });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isColorInfo(value: unknown): value is ColorInfo {
  return isRecord(value) && typeof value.name === "string" && typeof value.hexColor === "string";
}

function isJoinSessionRpcResult(value: unknown): value is JoinSessionRpcResult {
  return (
    isRecord(value) &&
    typeof value.participantId === "string" &&
    isColorInfo(value.myColor) &&
    isColorInfo(value.giftColor)
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

function mapDatabaseError(error: PostgrestErrorLike): HttpError {
  switch (error.code) {
    case PG_SESSION_NOT_FOUND:
      return new HttpError(404, "SESSION_NOT_FOUND", "No session found for this invite code");
    case PG_SESSION_NOT_ACTIVE:
      return new HttpError(409, "SESSION_NOT_ACTIVE", "This session is not open for joining");
    case PG_SESSION_FULL:
      return new HttpError(409, "SESSION_FULL", "This session is full");
    case PG_DUPLICATE_NAME:
      return new HttpError(409, "DUPLICATE_PARTICIPANT_NAME", "This name is already taken in this session", [
        { field: "participantName", message: "This name is already taken in this session" },
      ]);
    case PG_INVALID_ARGUMENT:
      return new HttpError(422, "VALIDATION_ERROR", error.message);
    case PGRST_FUNCTION_NOT_FOUND:
      console.error("[join-session] RPC join_session not found. Did you apply the migration?", error);
      return new HttpError(500, "SERVER_MISCONFIGURED", "Session service is not configured correctly");
    default:
      console.error("[join-session] Unexpected database error", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to join session");
  }
}

// =============================================================================
// Core logic
// =============================================================================

async function joinSession(admin: AdminClient, input: JoinSessionInput): Promise<JoinSessionResponse> {
  for (let attempt = 1; attempt <= MAX_INSERT_ATTEMPTS; attempt++) {
    const participantId = generateParticipantId();
    const browserToken = generateBrowserToken();
    const recoveryCode = generateRecoveryCode();

    // All checks, color locking/assignment and the participant insert run inside
    // ONE Postgres transaction (the RPC function body).
    const { data, error } = await admin.rpc("join_session", {
      p_invite_code: input.inviteCode,
      p_participant_id: participantId,
      p_participant_name: input.participantName,
      p_browser_token: browserToken,
      p_recovery_code: recoveryCode,
    });

    if (error) {
      if (error.code === PG_UNIQUE_VIOLATION && attempt < MAX_INSERT_ATTEMPTS) {
        console.warn(`[join-session] Unique collision on attempt ${attempt}, retrying`, error.message);
        continue;
      }
      if (error.code === PG_UNIQUE_VIOLATION) {
        console.error("[join-session] Exhausted retries on unique collisions", error);
        throw new HttpError(503, "CREDENTIALS_EXHAUSTED", "Could not generate unique credentials, please retry");
      }
      throw mapDatabaseError(error);
    }

    if (!isJoinSessionRpcResult(data)) {
      console.error("[join-session] Unexpected RPC result shape", data);
      throw new HttpError(500, "INVALID_DB_RESPONSE", "Unexpected response from database");
    }

    return {
      participantId: data.participantId,
      browserToken,
      recoveryCode,
      myColor: data.myColor,
      giftColor: data.giftColor,
    };
  }

  // Unreachable: the loop either returns or throws.
  throw new HttpError(500, "INTERNAL_ERROR", "Failed to join session");
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

      const validation = validateJoinSessionInput(body);
      if (!validation.ok) {
        throw new HttpError(422, "VALIDATION_ERROR", "Request validation failed", validation.errors);
      }

      const result = await joinSession(ctx.supabaseAdmin as unknown as AdminClient, validation.value);
      return Response.json(result, { status: 201 });
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err);
      }
      console.error("[join-session] Unhandled error", err);
      return errorResponse(new HttpError(500, "INTERNAL_ERROR", "Internal server error"));
    }
  }),
};

/* To invoke locally:

  1. supabase start && supabase db reset   (applies the migrations)
  2. supabase functions serve join-session
  3. curl -i --request POST 'http://127.0.0.1:54321/functions/v1/join-session' \
       --header 'apikey: <publishable key>' \
       --header 'Content-Type: application/json' \
       --data '{"inviteCode":"ABC234","participantName":"Maria"}'

  Status codes:
    201 joined | 400 invalid JSON | 404 unknown invite code | 405 wrong method
    409 session not active / full / duplicate name | 415 wrong content type
    422 validation | 503 credential collisions exhausted | 500 server error
*/
