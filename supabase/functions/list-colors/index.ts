// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

import { type FieldError, validateListColorsInput } from "./validation.ts";

// =============================================================================
// Types
// =============================================================================

interface CatalogColor {
  id: number;
  name: string;
  hexColor: string;
}

interface ListColorsResponse {
  colors: CatalogColor[];
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

/** Custom SQLSTATE raised by public.list_colors */
const PG_UNEXPECTED_ERROR = "LC001";
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

function isCatalogColor(value: unknown): value is CatalogColor {
  return (
    isRecord(value) &&
    typeof value.id === "number" &&
    Number.isInteger(value.id) &&
    typeof value.name === "string" &&
    typeof value.hexColor === "string"
  );
}

function isListColorsResponse(value: unknown): value is ListColorsResponse {
  return isRecord(value) && Array.isArray(value.colors) && value.colors.every(isCatalogColor);
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
    case PG_UNEXPECTED_ERROR:
      console.error("[list-colors] list_colors raised LC001", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to list colors");
    case PGRST_FUNCTION_NOT_FOUND:
      console.error("[list-colors] RPC list_colors not found. Did you apply the migration?", error);
      return new HttpError(500, "SERVER_MISCONFIGURED", "Color service is not configured correctly");
    default:
      console.error("[list-colors] Unexpected database error", error);
      return new HttpError(500, "DATABASE_ERROR", "Failed to list colors");
  }
}

// =============================================================================
// Core logic
// =============================================================================

async function listColors(admin: AdminClient): Promise<ListColorsResponse> {
  const { data, error } = await admin.rpc("list_colors", {});

  if (error) {
    throw mapDatabaseError(error);
  }

  if (!isListColorsResponse(data)) {
    console.error("[list-colors] Unexpected RPC result shape");
    throw new HttpError(500, "INVALID_DB_RESPONSE", "Unexpected response from database");
  }

  // Rebuild the response from whitelisted fields so nothing extra can leak,
  // even if the RPC is later changed to return more. Order comes from the RPC.
  return {
    colors: data.colors.map((c) => ({ id: c.id, name: c.name, hexColor: c.hexColor })),
  };
}

// =============================================================================
// Handler
// =============================================================================

// 'publishable': client-facing (Flutter app), 'secret': server-to-server.
// The catalog is not secret, so no token is required beyond the API key.
export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    try {
      if (req.method !== "POST") {
        throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST is supported");
      }

      const body = await readJsonBody(req);

      const validation = validateListColorsInput(body);
      if (!validation.ok) {
        throw new HttpError(422, "VALIDATION_ERROR", "Request validation failed", validation.errors);
      }

      const result = await listColors(ctx.supabaseAdmin as unknown as AdminClient);
      return Response.json(result, { status: 200 });
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err);
      }
      console.error("[list-colors] Unhandled error", err);
      return errorResponse(new HttpError(500, "INTERNAL_ERROR", "Internal server error"));
    }
  }),
};

/* To invoke locally:

  1. supabase start && supabase db reset   (applies the migrations)
  2. supabase functions serve list-colors
  3. curl -i --request POST 'http://127.0.0.1:54321/functions/v1/list-colors' \
       --header 'apikey: <publishable key>' \
       --header 'Content-Type: application/json' \
       --data '{}'

  Status codes:
    200 ok | 400 invalid JSON | 405 wrong method | 415 wrong content type
    422 unexpected input fields | 500 server error (LC001)
*/
