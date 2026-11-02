import 'package:dio/dio.dart';

import 'api_failure.dart';

/// Converts a [DioException] into an [ApiFailure].
ApiFailure mapDioException(DioException exception) {
  switch (exception.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const NetworkFailure(
        code: ApiErrorCodes.timeout,
        message: 'The request timed out',
      );
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return const NetworkFailure(
        code: ApiErrorCodes.networkError,
        message: 'Could not reach the server',
      );
    case DioExceptionType.cancel:
      return const CancelledFailure();
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      final response = exception.response;
      if (response != null) {
        return mapErrorResponse(response.statusCode ?? 0, response.data);
      }
      return NetworkFailure(
        code: ApiErrorCodes.networkError,
        message: exception.message ?? 'Unknown network error',
      );
  }
}

/// Converts an HTTP error status and the Edge Function error body
/// `{ "error": { "code", "message", "details"? } }` into an [ApiFailure].
///
/// Tolerates bodies that are missing, not JSON, or in another shape (e.g. a
/// gateway error page): the status alone then decides the failure type.
ApiFailure mapErrorResponse(int statusCode, Object? body) {
  final parsed = _ErrorBody.tryParse(body);
  final code = parsed?.code ?? _fallbackCode(statusCode);
  final message = parsed?.message ?? 'Request failed with status $statusCode';

  switch (statusCode) {
    case 400:
    case 405:
    case 415:
      return BadRequestFailure(code: code, message: message, statusCode: statusCode);
    case 403:
      return ForbiddenFailure(code: code, message: message, statusCode: statusCode);
    case 404:
      return NotFoundFailure(code: code, message: message, statusCode: statusCode);
    case 409:
      return ConflictFailure(code: code, message: message, statusCode: statusCode);
    case 422:
      if (code == ApiErrorCodes.unknownColors) {
        return UnknownColorsFailure(
          message: message,
          statusCode: statusCode,
          unknownColorIds: _parseUnknownColorIds(parsed?.details),
        );
      }
      return ValidationFailure(
        code: code,
        message: message,
        statusCode: statusCode,
        fieldErrors: _parseFieldErrors(parsed?.details),
      );
    case 503:
      return ServiceUnavailableFailure(code: code, message: message, statusCode: statusCode);
    default:
      return ServerFailure(code: code, message: message, statusCode: statusCode);
  }
}

/// Code used when the response has no recognizable `{ error: { code } }` body.
///
/// 404 maps to the generic [ApiErrorCodes.notFound]: a bodyless 404 almost
/// always means the route itself is missing (function not deployed, wrong
/// base URL), not that a session or participant does not exist. Every real
/// domain 404 from the Edge Functions carries its own code.
String _fallbackCode(int statusCode) {
  switch (statusCode) {
    case 404:
      return ApiErrorCodes.notFound;
    case 403:
      return ApiErrorCodes.forbidden;
    case 422:
      return ApiErrorCodes.validationError;
    case 415:
      return ApiErrorCodes.unsupportedMediaType;
    case 405:
      return ApiErrorCodes.methodNotAllowed;
    case 400:
      return ApiErrorCodes.invalidJson;
    default:
      return statusCode >= 500 ? ApiErrorCodes.internalError : ApiErrorCodes.unknown;
  }
}

/// `details: [{ "field": "...", "message": "..." }]`
List<FieldError> _parseFieldErrors(Object? details) {
  if (details is! List) return const [];
  final errors = <FieldError>[];
  for (final item in details) {
    if (item is Map) {
      final field = item['field'];
      final message = item['message'];
      if (field is String && message is String) {
        errors.add(FieldError(field: field, message: message));
      }
    }
  }
  return List.unmodifiable(errors);
}

/// `details: { "unknownColorIds": [1, 2] }`
List<int> _parseUnknownColorIds(Object? details) {
  if (details is! Map) return const [];
  final ids = details['unknownColorIds'];
  if (ids is! List) return const [];
  return List.unmodifiable(ids.whereType<num>().map((id) => id.toInt()));
}

class _ErrorBody {
  const _ErrorBody({required this.code, required this.message, this.details});

  final String code;
  final String message;
  final Object? details;

  static _ErrorBody? tryParse(Object? body) {
    if (body is! Map) return null;
    final error = body['error'];
    if (error is! Map) return null;
    final code = error['code'];
    final message = error['message'];
    if (code is! String || message is! String) return null;
    return _ErrorBody(code: code, message: message, details: error['details']);
  }
}
