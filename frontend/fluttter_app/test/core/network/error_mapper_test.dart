import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/core/network/error_mapper.dart';

Map<String, Object?> errorBody(String code, String message, [Object? details]) => {
      'error': {
        'code': code,
        'message': message,
        if (details != null) 'details': details,
      },
    };

void main() {
  group('mapErrorResponse', () {
    test('422 VALIDATION_ERROR maps field errors', () {
      final failure = mapErrorResponse(
        422,
        errorBody('VALIDATION_ERROR', 'Request validation failed', [
          {'field': 'participantName', 'message': 'participantName is required'},
        ]),
      );

      expect(failure, isA<ValidationFailure>());
      final validation = failure as ValidationFailure;
      expect(validation.code, ApiErrorCodes.validationError);
      expect(validation.errorFor('participantName'), 'participantName is required');
      expect(validation.errorFor('inviteCode'), isNull);
    });

    test('422 UNKNOWN_COLORS maps color ids', () {
      final failure = mapErrorResponse(
        422,
        errorBody('UNKNOWN_COLORS', 'unknown', {'unknownColorIds': [3, 7]}),
      );

      expect(failure, isA<UnknownColorsFailure>());
      expect((failure as UnknownColorsFailure).unknownColorIds, [3, 7]);
    });

    test('404 / 403 / 409 / 503 map to their failure types with the server code', () {
      expect(
        mapErrorResponse(404, errorBody('PARTICIPANT_NOT_FOUND', 'x')),
        isA<NotFoundFailure>().having((f) => f.code, 'code', ApiErrorCodes.participantNotFound),
      );
      expect(
        mapErrorResponse(403, errorBody('PARTICIPANT_INACTIVE', 'x')),
        isA<ForbiddenFailure>().having((f) => f.code, 'code', ApiErrorCodes.participantInactive),
      );
      expect(
        mapErrorResponse(409, errorBody('DUPLICATE_PARTICIPANT_NAME', 'x')),
        isA<ConflictFailure>().having((f) => f.code, 'code', ApiErrorCodes.duplicateParticipantName),
      );
      expect(
        mapErrorResponse(503, errorBody('INVITE_CODE_EXHAUSTED', 'x')),
        isA<ServiceUnavailableFailure>(),
      );
    });

    test('400 / 405 / 415 map to BadRequestFailure', () {
      expect(mapErrorResponse(400, errorBody('INVALID_JSON', 'x')), isA<BadRequestFailure>());
      expect(mapErrorResponse(405, errorBody('METHOD_NOT_ALLOWED', 'x')), isA<BadRequestFailure>());
      expect(mapErrorResponse(415, errorBody('UNSUPPORTED_MEDIA_TYPE', 'x')), isA<BadRequestFailure>());
    });

    test('404 without an error body maps to generic NOT_FOUND, not a domain code', () {
      for (final body in <Object?>[null, '', '<html>Not Found</html>', {'msg': 'x'}]) {
        final failure = mapErrorResponse(404, body);

        expect(failure, isA<NotFoundFailure>());
        expect(failure.code, ApiErrorCodes.notFound);
        expect(failure.code, isNot(ApiErrorCodes.sessionNotFound));
        expect(failure.code, isNot(ApiErrorCodes.participantNotFound));
      }
    });

    test('404 with an error body keeps the server domain code', () {
      expect(
        mapErrorResponse(404, errorBody('SESSION_NOT_FOUND', 'x')).code,
        ApiErrorCodes.sessionNotFound,
      );
    });

    test('non-JSON body falls back to the status code', () {
      final failure = mapErrorResponse(502, '<html>Bad Gateway</html>');

      expect(failure, isA<ServerFailure>());
      expect(failure.code, ApiErrorCodes.internalError);
      expect(failure.statusCode, 502);
    });
  });
}
