import 'package:json_annotation/json_annotation.dart';

import '../../core/network/api_failure.dart';

/// Parses a 2xx response body with [fromJson].
///
/// A body that does not match the model (missing field, wrong type, bad enum
/// or date) becomes a [ServerFailure] with code
/// [ApiErrorCodes.invalidResponse]. Only the exception TYPE is put in the
/// message: decode error messages can echo raw input, which may contain a
/// token or code.
///
/// Any other exception is rethrown unchanged.
T parseResponse<T>(
  String functionName,
  Map<String, dynamic> json,
  T Function(Map<String, dynamic> json) fromJson,
) {
  try {
    return fromJson(json);
  } on Object catch (e) {
    if (!_isDecodeError(e)) rethrow;
    throw ServerFailure(
      code: ApiErrorCodes.invalidResponse,
      message: 'Malformed $functionName response (${e.runtimeType})',
    );
  }
}

/// * [TypeError]: generated casts on a missing / wrongly typed field.
/// * [FormatException]: unparsable DateTime.
/// * [ArgumentError]: `$enumDecode` on a null enum value.
/// * [CheckedFromJsonException]: only if `checked: true` is enabled.
bool _isDecodeError(Object error) =>
    error is TypeError ||
    error is FormatException ||
    error is ArgumentError ||
    error is CheckedFromJsonException;
