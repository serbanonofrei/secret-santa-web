export interface CreateSessionInput {
  sessionName: string;
  maxParticipants: number;
  allowedColors: number[];
}

export interface FieldError {
  field: string;
  message: string;
}

export type ValidationResult =
  | { ok: true; value: CreateSessionInput }
  | { ok: false; errors: FieldError[] };

export const SESSION_NAME_MIN = 3;
export const SESSION_NAME_MAX = 100;
export const MAX_PARTICIPANTS_MIN = 2;
export const MAX_PARTICIPANTS_MAX = 100;
/** Sanity cap so a client cannot send an enormous array. */
export const ALLOWED_COLORS_MAX = 1000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

/** Counts Unicode code points, matching Postgres char_length(). */
function codePointLength(value: string): number {
  return Array.from(value).length;
}

export function validateCreateSessionInput(body: unknown): ValidationResult {
  if (!isRecord(body)) {
    return { ok: false, errors: [{ field: "body", message: "Request body must be a JSON object" }] };
  }

  const errors: FieldError[] = [];

  // --- sessionName -----------------------------------------------------------
  const rawName = body.sessionName;
  let sessionName = "";
  if (rawName === undefined || rawName === null) {
    errors.push({ field: "sessionName", message: "sessionName is required" });
  } else if (typeof rawName !== "string") {
    errors.push({ field: "sessionName", message: "sessionName must be a string" });
  } else {
    sessionName = rawName.trim();
    const length = codePointLength(sessionName);
    if (length === 0) {
      errors.push({ field: "sessionName", message: "sessionName is required" });
    } else if (length < SESSION_NAME_MIN || length > SESSION_NAME_MAX) {
      errors.push({
        field: "sessionName",
        message: `sessionName must be between ${SESSION_NAME_MIN} and ${SESSION_NAME_MAX} characters`,
      });
    }
  }

  // --- maxParticipants -------------------------------------------------------
  const rawMax = body.maxParticipants;
  let maxParticipants = 0;
  let maxParticipantsValid = false;
  if (rawMax === undefined || rawMax === null) {
    errors.push({ field: "maxParticipants", message: "maxParticipants is required" });
  } else if (typeof rawMax !== "number" || !Number.isInteger(rawMax)) {
    errors.push({ field: "maxParticipants", message: "maxParticipants must be an integer" });
  } else if (rawMax < MAX_PARTICIPANTS_MIN || rawMax > MAX_PARTICIPANTS_MAX) {
    errors.push({
      field: "maxParticipants",
      message: `maxParticipants must be between ${MAX_PARTICIPANTS_MIN} and ${MAX_PARTICIPANTS_MAX}`,
    });
  } else {
    maxParticipants = rawMax;
    maxParticipantsValid = true;
  }

  // --- allowedColors ---------------------------------------------------------
  const rawColors = body.allowedColors;
  let allowedColors: number[] = [];
  if (rawColors === undefined || rawColors === null) {
    errors.push({ field: "allowedColors", message: "allowedColors is required" });
  } else if (!Array.isArray(rawColors)) {
    errors.push({ field: "allowedColors", message: "allowedColors must be an array of integers" });
  } else if (rawColors.length > ALLOWED_COLORS_MAX) {
    errors.push({
      field: "allowedColors",
      message: `allowedColors must not contain more than ${ALLOWED_COLORS_MAX} entries`,
    });
  } else if (!rawColors.every(isPositiveInteger)) {
    errors.push({ field: "allowedColors", message: "allowedColors must contain only positive integers" });
  } else if (new Set(rawColors).size !== rawColors.length) {
    errors.push({ field: "allowedColors", message: "allowedColors must not contain duplicates" });
  } else {
    allowedColors = rawColors;
    if (maxParticipantsValid && allowedColors.length < maxParticipants) {
      errors.push({
        field: "allowedColors",
        message: `allowedColors must contain at least maxParticipants (${maxParticipants}) colors`,
      });
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return { ok: true, value: { sessionName, maxParticipants, allowedColors } };
}
