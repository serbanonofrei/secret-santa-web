// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

import { type CloseSessionInput, type FieldError, validateCloseSessionInput } from "./validation.ts";

// =============================================================================
// Types
// =============================================================================

interface CloseSessionResponse {
  sessionId: string;
  status: "CLOSED";
  published: boolean;
  sessionName: string;
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

/** Custom SQLSTATEs raised by public.close_session */
const PG_SESSION_NOT_FOUND = "CS001";
const PG_INVALID_ORGANIZER = "CS002";
const PG_INVALID_ARGUMENT = "CS003";
const PG_ALREADY_CLOSED = "CS004";
const PG_NOT_ACTIVE = "CS005";
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

function isCloseSessionResponse(value: unknown): value is CloseSessionResponse {
  return (
    isRecord(value) &&
    typeof value.sessionId === "string" &&
    value.status === "CLOSED" &&
    typeof value.published === "boolean" &&
    typeof value.sessionName === "string"
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
      return new HttpError(404, "SESSION_NOT_FOUND", "Session not found");
    case PG_INVALID_ORGANIZER:
      return new HttpError(403, "FORBIDDEN", "Organizer token is not valid for this session");
    case PG_INVALID_ARGUMENT:
      return new HttpError(422, "VALIDATION_ERROR", "Request validation failed");
    case PG_ALREADY_CLOSED:
      return new HttpError(409, "SESSION_ALREADY_CLOSED", "Session is already closed");
    case PG_NOT_ACTIVE:
      return new HttpError(409, "SESSION_NOT_ACTIVE", "Only active sessions can be closed");
    case PGRST_FUNCTION_NOT_FOUND:
      console.error("[close-session] RPC close_session not found. Did you apply the migration?", error);
      return new HttpError(500, "SERVER_MISCONFIGURED", "Session service is not configured correctly");
    default:
      console.error("[close-session] Unexpected database error", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to close session");
  }
}

// =============================================================================
// Core logic
// =============================================================================

async function closeSession(admin: AdminClient, input: CloseSessionInput): Promise<CloseSessionResponse> {
  // Lock, authorization, state check and update run inside ONE Postgres
  // transaction (the RPC function body). Participants and colors are untouched.
  const { data, error } = await admin.rpc("close_session", {
    p_session_id: input.sessionId,
    p_organizer_token: input.organizerToken,
  });

  if (error) {
    throw mapDatabaseError(error);
  }

  if (!isCloseSessionResponse(data)) {
    console.error("[close-session] Unexpected RPC result shape");
    throw new HttpError(500, "INVALID_DB_RESPONSE", "Unexpected response from database");
  }

  return {
    sessionId: data.sessionId,
    status: data.status,
    published: data.published,
    sessionName: data.sessionName,
  };
}

// =============================================================================
// Handler
// =============================================================================

// 'publishable': client-facing (Flutter app), 'secret': server-to-server.
// Authorization is the organizer token, verified inside the RPC.
export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    try {
      if (req.method !== "POST") {
        throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST is supported");
      }

      const body = await readJsonBody(req);

      const validation = validateCloseSessionInput(body);
      if (!validation.ok) {
        throw new HttpError(422, "VALIDATION_ERROR", "Request validation failed", validation.errors);
      }

      const result = await closeSession(ctx.supabaseAdmin as unknown as AdminClient, validation.value);
      return Response.json(result, { status: 200 });
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err);
      }
      console.error("[close-session] Unhandled error", err);
      return errorResponse(new HttpError(500, "INTERNAL_ERROR", "Internal server error"));
    }
  }),
};

/* To invoke locally:

  1. supabase start && supabase db reset   (applies the migrations)
  2. supabase functions serve close-session
  3. curl -i --request POST 'http://127.0.0.1:54321/functions/v1/close-session' \
       --header 'apikey: <publishable key>' \
       --header 'Content-Type: application/json' \
       --data '{"sessionId":"<uuid>","organizerToken":"ORG_<uuid>"}'

  Status codes:
    200 closed | 400 invalid JSON | 403 wrong organizer token | 404 session not found
    405 wrong method | 409 already closed / not ACTIVE | 415 wrong content type
    422 validation | 500 server error
*/
