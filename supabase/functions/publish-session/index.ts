// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

// =============================================================================
// Types
// =============================================================================

interface PublishSessionInput {
  sessionId: string;
  organizerToken: string;
}

interface PublishSessionResponse {
  sessionId: string;
  sessionName: string;
  inviteCode: string;
  maxParticipants: number;
  status: "ACTIVE";
  published: true;
  draft: false;
  colorCount: number;
}

interface FieldError {
  field: string;
  message: string;
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

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ORGANIZER_TOKEN_PATTERN = /^ORG_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Custom SQLSTATEs raised by public.publish_session */
const PG_SESSION_NOT_FOUND = "SP001";
const PG_INVALID_ORGANIZER = "SP002";
const PG_NOT_DRAFT = "SP003";
const PG_NOT_ENOUGH_COLORS = "SP004";
const PG_INVALID_ARGUMENT = "SP005";
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

function validateInput(body: unknown): PublishSessionInput {
  if (!isRecord(body)) {
    throw new HttpError(422, "VALIDATION_ERROR", "Request body must be a JSON object");
  }

  const errors: FieldError[] = [];
  const { sessionId, organizerToken } = body;

  if (typeof sessionId !== "string" || sessionId.trim() === "") {
    errors.push({ field: "sessionId", message: "sessionId is required" });
  } else if (!UUID_PATTERN.test(sessionId.trim())) {
    errors.push({ field: "sessionId", message: "sessionId must be a valid UUID" });
  }

  if (typeof organizerToken !== "string" || organizerToken.trim() === "") {
    errors.push({ field: "organizerToken", message: "organizerToken is required" });
  } else if (!ORGANIZER_TOKEN_PATTERN.test(organizerToken.trim())) {
    errors.push({ field: "organizerToken", message: "organizerToken has an invalid format" });
  }

  if (errors.length > 0) {
    throw new HttpError(422, "VALIDATION_ERROR", "Request validation failed", errors);
  }

  return {
    sessionId: (sessionId as string).trim(),
    organizerToken: (organizerToken as string).trim(),
  };
}

function isPublishSessionResponse(value: unknown): value is PublishSessionResponse {
  return (
    isRecord(value) &&
    typeof value.sessionId === "string" &&
    typeof value.sessionName === "string" &&
    typeof value.inviteCode === "string" &&
    typeof value.maxParticipants === "number" &&
    value.status === "ACTIVE" &&
    value.published === true &&
    value.draft === false &&
    typeof value.colorCount === "number"
  );
}

function mapDatabaseError(error: PostgrestErrorLike): HttpError {
  switch (error.code) {
    case PG_SESSION_NOT_FOUND:
      return new HttpError(404, "SESSION_NOT_FOUND", "Session not found");
    case PG_INVALID_ORGANIZER:
      return new HttpError(403, "FORBIDDEN", "Organizer token is not valid for this session");
    case PG_NOT_DRAFT:
      return new HttpError(409, "SESSION_NOT_DRAFT", "Session has already been published or is not in DRAFT state");
    case PG_NOT_ENOUGH_COLORS:
      return new HttpError(422, "NOT_ENOUGH_COLORS", "Session needs at least 2 colors to be published");
    case PG_INVALID_ARGUMENT:
      return new HttpError(422, "VALIDATION_ERROR", error.message);
    case PGRST_FUNCTION_NOT_FOUND:
      console.error("[publish-session] RPC publish_session not found. Did you apply the migration?", error);
      return new HttpError(500, "SERVER_MISCONFIGURED", "Session service is not configured correctly");
    default:
      console.error("[publish-session] Unexpected database error", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to publish session");
  }
}

// =============================================================================
// Core logic
// =============================================================================

async function publishSession(admin: AdminClient, input: PublishSessionInput): Promise<PublishSessionResponse> {
  // Chain generation, target_color_id updates and the status change all happen
  // inside ONE Postgres transaction (the RPC function body).
  const { data, error } = await admin.rpc("publish_session", {
    p_session_id: input.sessionId,
    p_organizer_token: input.organizerToken,
  });

  if (error) {
    throw mapDatabaseError(error);
  }

  if (!isPublishSessionResponse(data)) {
    console.error("[publish-session] Unexpected RPC result shape", data);
    throw new HttpError(500, "INVALID_DB_RESPONSE", "Unexpected response from database");
  }

  return data;
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
      const input = validateInput(body);

      const result = await publishSession(ctx.supabaseAdmin as unknown as AdminClient, input);
      return Response.json(result, { status: 200 });
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err);
      }
      console.error("[publish-session] Unhandled error", err);
      return errorResponse(new HttpError(500, "INTERNAL_ERROR", "Internal server error"));
    }
  }),
};

/* To invoke locally:

  1. supabase start && supabase db reset   (applies the migrations)
  2. supabase functions serve publish-session
  3. curl -i --request POST 'http://127.0.0.1:54321/functions/v1/publish-session' \
       --header 'apikey: <publishable key>' \
       --header 'Content-Type: application/json' \
       --data '{"sessionId":"<uuid from create-session>","organizerToken":"ORG_<uuid>"}'

  Status codes:
    200 published | 400 invalid JSON | 403 wrong organizer token | 404 session not found
    405 wrong method | 409 already published / not DRAFT | 415 wrong content type
    422 validation / fewer than 2 colors | 500 server error
*/
