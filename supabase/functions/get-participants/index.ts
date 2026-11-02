// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

import { type FieldError, type GetParticipantsInput, validateGetParticipantsInput } from "./validation.ts";

// =============================================================================
// Types
// =============================================================================

interface ParticipantSummary {
  participantId: string;
  participantName: string;
}

interface GetParticipantsResponse {
  sessionId: string;
  sessionName: string;
  status: string;
  published: boolean;
  joinedCount: number;
  maxParticipants: number;
  participants: ParticipantSummary[];
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

/** Custom SQLSTATEs raised by public.get_participants */
const PG_SESSION_NOT_FOUND = "GP001";
const PG_INVALID_ORGANIZER = "GP002";
const PG_INVALID_ARGUMENT = "GP003";
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

function isParticipantSummary(value: unknown): value is ParticipantSummary {
  return (
    isRecord(value) &&
    typeof value.participantId === "string" &&
    typeof value.participantName === "string"
  );
}

function isGetParticipantsResponse(value: unknown): value is GetParticipantsResponse {
  return (
    isRecord(value) &&
    typeof value.sessionId === "string" &&
    typeof value.sessionName === "string" &&
    typeof value.status === "string" &&
    typeof value.published === "boolean" &&
    typeof value.joinedCount === "number" &&
    typeof value.maxParticipants === "number" &&
    Array.isArray(value.participants) &&
    value.participants.every(isParticipantSummary)
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
    case PGRST_FUNCTION_NOT_FOUND:
      console.error("[get-participants] RPC get_participants not found. Did you apply the migration?", error);
      return new HttpError(500, "SERVER_MISCONFIGURED", "Session service is not configured correctly");
    default:
      console.error("[get-participants] Unexpected database error", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to load participants");
  }
}

// =============================================================================
// Core logic
// =============================================================================

async function getParticipants(admin: AdminClient, input: GetParticipantsInput): Promise<GetParticipantsResponse> {
  const { data, error } = await admin.rpc("get_participants", {
    p_session_id: input.sessionId,
    p_organizer_token: input.organizerToken,
  });

  if (error) {
    throw mapDatabaseError(error);
  }

  if (!isGetParticipantsResponse(data)) {
    console.error("[get-participants] Unexpected RPC result shape");
    throw new HttpError(500, "INVALID_DB_RESPONSE", "Unexpected response from database");
  }

  // Rebuild the response from whitelisted fields so nothing extra can leak,
  // even if the RPC is later changed to return more. Order comes from the RPC.
  return {
    sessionId: data.sessionId,
    sessionName: data.sessionName,
    status: data.status,
    published: data.published,
    joinedCount: data.joinedCount,
    maxParticipants: data.maxParticipants,
    participants: data.participants.map((p) => ({
      participantId: p.participantId,
      participantName: p.participantName,
    })),
  };
}

// =============================================================================
// Handler
// =============================================================================

// 'publishable': client-facing (Flutter app), 'secret': server-to-server.
// Authorization is the organizer token, verified inside the RPC.
// POST (not GET) keeps the organizer token out of URLs and logs.
export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    try {
      if (req.method !== "POST") {
        throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST is supported");
      }

      const body = await readJsonBody(req);

      const validation = validateGetParticipantsInput(body);
      if (!validation.ok) {
        throw new HttpError(422, "VALIDATION_ERROR", "Request validation failed", validation.errors);
      }

      const result = await getParticipants(ctx.supabaseAdmin as unknown as AdminClient, validation.value);
      return Response.json(result, {
        status: 200,
        headers: { "Cache-Control": "no-store" },
      });
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err);
      }
      console.error("[get-participants] Unhandled error", err);
      return errorResponse(new HttpError(500, "INTERNAL_ERROR", "Internal server error"));
    }
  }),
};

/* To invoke locally:

  1. supabase start && supabase db reset   (applies the migrations)
  2. supabase functions serve get-participants
  3. curl -i --request POST 'http://127.0.0.1:54321/functions/v1/get-participants' \
       --header 'apikey: <publishable key>' \
       --header 'Content-Type: application/json' \
       --data '{"sessionId":"<uuid>","organizerToken":"ORG_<uuid>"}'

  Status codes:
    200 ok | 400 invalid JSON | 403 wrong organizer token | 404 session not found
    405 wrong method | 415 wrong content type | 422 validation | 500 server error
*/
