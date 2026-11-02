export interface CloseSessionInput {
  /** Trimmed, lower-cased UUID. */
  sessionId: string;
  /** Trimmed. */
  organizerToken: string;
}

export interface FieldError {
  field: string;
  message: string;
}

export type ValidationResult =
  | { ok: true; value: CloseSessionInput }
  | { ok: false; errors: FieldError[] };

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Same format create-session generates: ORG_<uuid>. */
const ORGANIZER_TOKEN_PATTERN = /^ORG_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateCloseSessionInput(body: unknown): ValidationResult {
  if (!isRecord(body)) {
    return { ok: false, errors: [{ field: "body", message: "Request body must be a JSON object" }] };
  }

  const errors: FieldError[] = [];

  // --- sessionId -------------------------------------------------------------
  const rawSessionId = body.sessionId;
  let sessionId = "";
  if (rawSessionId === undefined || rawSessionId === null) {
    errors.push({ field: "sessionId", message: "sessionId is required" });
  } else if (typeof rawSessionId !== "string") {
    errors.push({ field: "sessionId", message: "sessionId must be a string" });
  } else {
    sessionId = rawSessionId.trim().toLowerCase();
    if (sessionId === "") {
      errors.push({ field: "sessionId", message: "sessionId is required" });
    } else if (!UUID_PATTERN.test(sessionId)) {
      errors.push({ field: "sessionId", message: "sessionId must be a valid UUID" });
    }
  }

  // --- organizerToken --------------------------------------------------------
  const rawToken = body.organizerToken;
  let organizerToken = "";
  if (rawToken === undefined || rawToken === null) {
    errors.push({ field: "organizerToken", message: "organizerToken is required" });
  } else if (typeof rawToken !== "string") {
    errors.push({ field: "organizerToken", message: "organizerToken must be a string" });
  } else {
    organizerToken = rawToken.trim();
    if (organizerToken === "") {
      errors.push({ field: "organizerToken", message: "organizerToken is required" });
    } else if (!ORGANIZER_TOKEN_PATTERN.test(organizerToken)) {
      errors.push({ field: "organizerToken", message: "organizerToken has an invalid format" });
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return { ok: true, value: { sessionId, organizerToken } };
}
