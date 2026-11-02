export interface RecoverAssignmentInput {
  /** Trimmed and upper-cased, format XXXX-XXXX-XXXX. */
  recoveryCode: string;
}

export interface FieldError {
  field: string;
  message: string;
}

export type ValidationResult =
  | { ok: true; value: RecoverAssignmentInput }
  | { ok: false; errors: FieldError[] };

/** Same format join-session generates. */
const RECOVERY_CODE_PATTERN =
  /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}(-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}){2}$/;

/** Only these keys are accepted, so no other lookup key can be smuggled in. */
const ALLOWED_KEYS: ReadonlySet<string> = new Set(["recoveryCode"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateRecoverAssignmentInput(body: unknown): ValidationResult {
  if (!isRecord(body)) {
    return { ok: false, errors: [{ field: "body", message: "Request body must be a JSON object" }] };
  }

  const errors: FieldError[] = [];

  // --- unknown keys ----------------------------------------------------------
  for (const key of Object.keys(body)) {
    if (!ALLOWED_KEYS.has(key)) {
      errors.push({ field: key, message: "Unknown field; recoveryCode is the only accepted field" });
    }
  }

  // --- recoveryCode ----------------------------------------------------------
  const rawCode = body.recoveryCode;
  let recoveryCode = "";
  if (rawCode === undefined || rawCode === null) {
    errors.push({ field: "recoveryCode", message: "recoveryCode is required" });
  } else if (typeof rawCode !== "string") {
    errors.push({ field: "recoveryCode", message: "recoveryCode must be a string" });
  } else {
    // Codes are shown in upper case; accept lower-case typing from users.
    recoveryCode = rawCode.trim().toUpperCase();
    if (recoveryCode === "") {
      errors.push({ field: "recoveryCode", message: "recoveryCode is required" });
    } else if (!RECOVERY_CODE_PATTERN.test(recoveryCode)) {
      errors.push({ field: "recoveryCode", message: "recoveryCode must have the format XXXX-XXXX-XXXX" });
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return { ok: true, value: { recoveryCode } };
}
