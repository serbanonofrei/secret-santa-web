/// Error codes returned by the Edge Functions in `{ error: { code } }`,
/// plus client-side codes for failures that never reached the server.
///
/// The UI reacts to these codes, never to the server message text.
abstract final class ApiErrorCodes {
  // --- Generic request errors ------------------------------------------------
  static const validationError = 'VALIDATION_ERROR';
  static const invalidJson = 'INVALID_JSON';
  static const unsupportedMediaType = 'UNSUPPORTED_MEDIA_TYPE';
  static const methodNotAllowed = 'METHOD_NOT_ALLOWED';

  // --- Not found (404) -------------------------------------------------------
  static const sessionNotFound = 'SESSION_NOT_FOUND';
  static const participantNotFound = 'PARTICIPANT_NOT_FOUND';

  // --- Forbidden (403) -------------------------------------------------------
  static const forbidden = 'FORBIDDEN';
  static const participantInactive = 'PARTICIPANT_INACTIVE';

  // --- Conflict (409) --------------------------------------------------------
  static const sessionNotActive = 'SESSION_NOT_ACTIVE';
  static const sessionFull = 'SESSION_FULL';
  static const duplicateParticipantName = 'DUPLICATE_PARTICIPANT_NAME';
  static const sessionNotDraft = 'SESSION_NOT_DRAFT';
  static const sessionAlreadyClosed = 'SESSION_ALREADY_CLOSED';
  static const assignmentUnavailable = 'ASSIGNMENT_UNAVAILABLE';

  // --- Unprocessable (422) ---------------------------------------------------
  static const unknownColors = 'UNKNOWN_COLORS';
  static const notEnoughColors = 'NOT_ENOUGH_COLORS';
  static const invalidReference = 'INVALID_REFERENCE';

  // --- Service unavailable (503) ---------------------------------------------
  static const inviteCodeExhausted = 'INVITE_CODE_EXHAUSTED';
  static const credentialsExhausted = 'CREDENTIALS_EXHAUSTED';

  // --- Server (500) ----------------------------------------------------------
  static const serverMisconfigured = 'SERVER_MISCONFIGURED';
  static const databaseError = 'DATABASE_ERROR';
  static const invalidDbResponse = 'INVALID_DB_RESPONSE';
  static const internalError = 'INTERNAL_ERROR';

  // --- Client-side only ------------------------------------------------------
  /// 404 without a recognizable error body (e.g. function not deployed, wrong
  /// base URL). Deliberately NOT a domain code: it must never be mistaken for
  /// SESSION_NOT_FOUND or PARTICIPANT_NOT_FOUND.
  static const notFound = 'NOT_FOUND';
  static const networkError = 'NETWORK_ERROR';
  static const timeout = 'TIMEOUT';
  static const cancelled = 'CANCELLED';
  static const invalidResponse = 'INVALID_RESPONSE';
  static const unknown = 'UNKNOWN';
}

/// A field-level validation error from `error.details[]`.
class FieldError {
  const FieldError({required this.field, required this.message});

  final String field;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is FieldError && other.field == field && other.message == message;

  @override
  int get hashCode => Object.hash(field, message);

  @override
  String toString() => 'FieldError($field: $message)';
}

/// Every failure an API call can produce. Services throw these; controllers
/// switch over them exhaustively.
sealed class ApiFailure implements Exception {
  const ApiFailure({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// Server `error.code`, or one of the client-side [ApiErrorCodes].
  final String code;

  /// Server `error.message` (English, for logs) or a client-side description.
  final String message;

  /// HTTP status, or null when no response was received.
  final int? statusCode;

  @override
  String toString() => '$runtimeType(code: $code, status: $statusCode, message: $message)';
}

/// 422 with field errors.
final class ValidationFailure extends ApiFailure {
  const ValidationFailure({
    required super.code,
    required super.message,
    super.statusCode,
    this.fieldErrors = const [],
  });

  final List<FieldError> fieldErrors;

  /// First error message for [field], or null.
  String? errorFor(String field) {
    for (final error in fieldErrors) {
      if (error.field == field) return error.message;
    }
    return null;
  }
}

/// 422 `UNKNOWN_COLORS` from create-session.
final class UnknownColorsFailure extends ApiFailure {
  const UnknownColorsFailure({
    required super.message,
    super.statusCode,
    this.unknownColorIds = const [],
  }) : super(code: ApiErrorCodes.unknownColors);

  final List<int> unknownColorIds;
}

/// 400 / 405 / 415: the app sent a malformed request (a client bug).
final class BadRequestFailure extends ApiFailure {
  const BadRequestFailure({required super.code, required super.message, super.statusCode});
}

/// 404.
final class NotFoundFailure extends ApiFailure {
  const NotFoundFailure({required super.code, required super.message, super.statusCode});
}

/// 403.
final class ForbiddenFailure extends ApiFailure {
  const ForbiddenFailure({required super.code, required super.message, super.statusCode});
}

/// 409.
final class ConflictFailure extends ApiFailure {
  const ConflictFailure({required super.code, required super.message, super.statusCode});
}

/// 503: transient, safe to retry.
final class ServiceUnavailableFailure extends ApiFailure {
  const ServiceUnavailableFailure({required super.code, required super.message, super.statusCode});
}

/// 5xx (other than 503), unknown statuses, or an unexpected response format.
final class ServerFailure extends ApiFailure {
  const ServerFailure({required super.code, required super.message, super.statusCode});
}

/// No response: offline, DNS, TLS or timeout.
/// Stored credentials must NEVER be deleted because of this failure.
final class NetworkFailure extends ApiFailure {
  const NetworkFailure({required super.code, required super.message}) : super(statusCode: null);
}

/// The request was cancelled by the app.
final class CancelledFailure extends ApiFailure {
  const CancelledFailure()
      : super(code: ApiErrorCodes.cancelled, message: 'The request was cancelled', statusCode: null);
}
