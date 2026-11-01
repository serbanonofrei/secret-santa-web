export interface GetMyAssignmentInput {
  /** Trimmed. */
  browserToken: string;
}

export interface FieldError {
  field: string;
  message: string;
}

export type ValidationResult =
  | { ok: true; value: GetMyAssignmentInput }
  | { ok: false; errors: FieldError[] };

/** Same format join-session generates: BT_ + 43 base64url chars (256 bits). */
const BROWSER_TOKEN_PATTERN = /^BT_[A-Za-z0-9_-]{43}$/;

/** Only these keys are accepted, so no other lookup key can be smuggled in. */
const ALLOWED_KEYS: ReadonlySet<string> = new Set(["browserToken"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateGetMyAssignmentInput(body: unknown): ValidationResult {
  if (!isRecord(body)) {
    return { ok: false, errors: [{ field: "body", message: "Request body must be a JSON object" }] };
  }

  const errors: FieldError[] = [];

  // --- unknown keys ----------------------------------------------------------
  for (const key of Object.keys(body)) {
    if (!ALLOWED_KEYS.has(key)) {
      errors.push({ field: key, message: "Unknown field; browserToken is the only accepted field" });
    }
  }

  // --- browserToken ----------------------------------------------------------
  const rawToken = body.browserToken;
  let browserToken = "";
  if (rawToken === undefined || rawToken === null) {
    errors.push({ field: "browserToken", message: "browserToken is required" });
  } else if (typeof rawToken !== "string") {
    errors.push({ field: "browserToken", message: "browserToken must be a string" });
  } else {
    browserToken = rawToken.trim();
    if (browserToken === "") {
      errors.push({ field: "browserToken", message: "browserToken is required" });
    } else if (!BROWSER_TOKEN_PATTERN.test(browserToken)) {
      errors.push({ field: "browserToken", message: "browserToken has an invalid format" });
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return { ok: true, value: { browserToken } };
}
