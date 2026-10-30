export interface JoinSessionInput {
  /** Trimmed and upper-cased. */
  inviteCode: string;
  /** NFC-normalized, whitespace collapsed, trimmed (same as the stored name). */
  participantName: string;
}

export interface FieldError {
  field: string;
  message: string;
}

export type ValidationResult =
  | { ok: true; value: JoinSessionInput }
  | { ok: false; errors: FieldError[] };

export const PARTICIPANT_NAME_MIN = 1;
export const PARTICIPANT_NAME_MAX = 100;

const INVITE_CODE_PATTERN = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Counts Unicode code points, matching Postgres char_length(). */
function codePointLength(value: string): number {
  return Array.from(value).length;
}

/**
 * Display form of a participant name. Mirrors the SQL in public.join_session:
 * NFC, collapse whitespace runs to one space, trim.
 */
export function toDisplayName(raw: string): string {
  return raw.normalize("NFC").replace(/\s+/g, " ").trim();
}

export function validateJoinSessionInput(body: unknown): ValidationResult {
  if (!isRecord(body)) {
    return { ok: false, errors: [{ field: "body", message: "Request body must be a JSON object" }] };
  }

  const errors: FieldError[] = [];

  // --- inviteCode ------------------------------------------------------------
  const rawCode = body.inviteCode;
  let inviteCode = "";
  if (rawCode === undefined || rawCode === null) {
    errors.push({ field: "inviteCode", message: "inviteCode is required" });
  } else if (typeof rawCode !== "string") {
    errors.push({ field: "inviteCode", message: "inviteCode must be a string" });
  } else {
    inviteCode = rawCode.trim().toUpperCase();
    if (inviteCode === "") {
      errors.push({ field: "inviteCode", message: "inviteCode is required" });
    } else if (!INVITE_CODE_PATTERN.test(inviteCode)) {
      errors.push({ field: "inviteCode", message: "inviteCode must be a 6-character invite code" });
    }
  }

  // --- participantName -------------------------------------------------------
  const rawName = body.participantName;
  let participantName = "";
  if (rawName === undefined || rawName === null) {
    errors.push({ field: "participantName", message: "participantName is required" });
  } else if (typeof rawName !== "string") {
    errors.push({ field: "participantName", message: "participantName must be a string" });
  } else {
    participantName = toDisplayName(rawName);
    const length = codePointLength(participantName);
    if (length === 0) {
      errors.push({ field: "participantName", message: "participantName is required" });
    } else if (length < PARTICIPANT_NAME_MIN || length > PARTICIPANT_NAME_MAX) {
      errors.push({
        field: "participantName",
        message: `participantName must be between ${PARTICIPANT_NAME_MIN} and ${PARTICIPANT_NAME_MAX} characters`,
      });
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return { ok: true, value: { inviteCode, participantName } };
}
