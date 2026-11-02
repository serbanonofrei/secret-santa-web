/** list-colors takes no input; the body must be an empty JSON object. */
export type ListColorsInput = Record<string, never>;

export interface FieldError {
  field: string;
  message: string;
}

export type ValidationResult =
  | { ok: true; value: ListColorsInput }
  | { ok: false; errors: FieldError[] };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateListColorsInput(body: unknown): ValidationResult {
  if (!isRecord(body)) {
    return { ok: false, errors: [{ field: "body", message: "Request body must be a JSON object" }] };
  }

  const errors: FieldError[] = Object.keys(body).map((key) => ({
    field: key,
    message: "Unknown field; list-colors accepts no input fields",
  }));

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return { ok: true, value: {} };
}
