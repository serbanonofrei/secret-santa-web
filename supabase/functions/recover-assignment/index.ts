// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

import { type FieldError, type RecoverAssignmentInput, validateRecoverAssignmentInput } from "./validation.ts";

// =============================================================================
// Types
// =============================================================================

interface ColorInfo {
  name: string;
  hexColor: string;
}

interface RecoverAssignmentResponse {
  participantId: string;
  participantName: string;
  browserToken: string;
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

/** Custom SQLSTATEs raised by public.recover_assignment */
const PG_PARTICIPANT_NOT_FOUND = "RA001";
const PG_PARTICIPANT_INACTIVE = "RA002";
const PG_ASSIGNMENT_UNAVAILABLE = "RA003";
const PG_INVALID_ARGUMENT = "RA004";
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

function isRecoverAssignmentResponse(value: unknown): value is RecoverAssignmentResponse {
  return (
    isRecord(value) &&
    typeof value.participantId === "string" &&
    typeof value.participantName === "string" &&
    typeof value.browserToken === "string" &&
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

/**
 * Maps a database error to an HttpError. Client messages are fixed strings;
 * raw database messages are only logged (they never contain the code or token).
 */
function mapDatabaseError(error: PostgrestErrorLike): HttpError {
  switch (error.code) {
    case PG_PARTICIPANT_NOT_FOUND:
      return new HttpError(404, "PARTICIPANT_NOT_FOUND", "No participant found for this recovery code");
    case PG_PARTICIPANT_INACTIVE:
      return new HttpError(403, "PARTICIPANT_INACTIVE", "Participant is no longer active");
    case PG_ASSIGNMENT_UNAVAILABLE:
      console.warn("[recover-assignment] Assignment unavailable:", error.message);
      return new HttpError(409, "ASSIGNMENT_UNAVAILABLE", "Assignment is not available");
    case PG_INVALID_ARGUMENT:
      return new HttpError(422, "VALIDATION_ERROR", "Request validation failed");
    case PGRST_FUNCTION_NOT_FOUND:
      console.error("[recover-assignment] RPC recover_assignment not found. Did you apply the migration?", error);
      return new HttpError(500, "SERVER_MISCONFIGURED", "Assignment service is not configured correctly");
    default:
      console.error("[recover-assignment] Unexpected database error", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to recover assignment");
  }
}

// =============================================================================
// Core logic
// =============================================================================

async function recoverAssignment(
  admin: AdminClient,
  input: RecoverAssignmentInput,
): Promise<RecoverAssignmentResponse> {
  // recoveryCode is the ONLY lookup key passed to the database.
  const { data, error } = await admin.rpc("recover_assignment", {
    p_recovery_code: input.recoveryCode,
  });

  if (error) {
    throw mapDatabaseError(error);
  }

  if (!isRecoverAssignmentResponse(data)) {
    console.error("[recover-assignment] Unexpected RPC result shape");
    throw new HttpError(500, "INVALID_DB_RESPONSE", "Unexpected response from database");
  }

  // Rebuild the response from whitelisted fields so nothing extra can leak,
  // even if the RPC is later changed to return more.
  return {
    participantId: data.participantId,
    participantName: data.participantName,
    browserToken: data.browserToken,
    myColor: { name: data.myColor.name, hexColor: data.myColor.hexColor },
    giftColor: { name: data.giftColor.name, hexColor: data.giftColor.hexColor },
  };
}

// =============================================================================
// Handler
// =============================================================================

// 'publishable': client-facing (Flutter app), 'secret': server-to-server.
// Authorization is the recovery code, verified inside the RPC.
// POST (not GET) keeps the code out of URLs, proxy logs and browser history.
export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    try {
      if (req.method !== "POST") {
        throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST is supported");
      }

      const body = await readJsonBody(req);

      const validation = validateRecoverAssignmentInput(body);
      if (!validation.ok) {
        throw new HttpError(422, "VALIDATION_ERROR", "Request validation failed", validation.errors);
      }

      const result = await recoverAssignment(ctx.supabaseAdmin as unknown as AdminClient, validation.value);
      return Response.json(result, {
        status: 200,
        headers: { "Cache-Control": "no-store" },
      });
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err);
      }
      console.error("[recover-assignment] Unhandled error", err);
      return errorResponse(new HttpError(500, "INTERNAL_ERROR", "Internal server error"));
    }
  }),
};

/* To invoke locally:

  1. supabase start && supabase db reset   (applies the migrations)
  2. supabase functions serve recover-assignment
  3. curl -i --request POST 'http://127.0.0.1:54321/functions/v1/recover-assignment' \
       --header 'apikey: <publishable key>' \
       --header 'Content-Type: application/json' \
       --data '{"recoveryCode":"ABCD-EFGH-JKLM"}'

  Status codes:
    200 ok | 400 invalid JSON | 403 inactive participant | 404 participant not found
    405 wrong method | 409 assignment unavailable | 415 wrong content type
    422 validation | 500 server error
*/
