import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/core/network/error_mapper.dart';
import 'package:secret_santa/shared/errors/failure_messages.dart';

/// Server message used in every failure below. It must never reach the UI.
const serverText = 'SERVER-SIDE TEXT 42';

ApiFailure failureFor(int status, String code) => mapErrorResponse(status, {
      'error': {
        'code': code,
        'message': serverText,
        'details': [
          {'field': 'participantName', 'message': serverText},
          {'field': 'inviteCode', 'message': serverText},
          {'field': 'recoveryCode', 'message': serverText},
        ],
      },
    });

void main() {
  /// Every backend code with the HTTP status the Edge Functions send it with.
  const backendCodes = <String, int>{
    // Organizer
    ApiErrorCodes.sessionNotDraft: 409,
    ApiErrorCodes.sessionAlreadyClosed: 409,
    ApiErrorCodes.unknownColors: 422,
    ApiErrorCodes.notEnoughColors: 422,
    ApiErrorCodes.forbidden: 403,
    ApiErrorCodes.inviteCodeExhausted: 503,
    ApiErrorCodes.invalidReference: 422,
    // Participant
    ApiErrorCodes.sessionNotFound: 404,
    ApiErrorCodes.sessionNotActive: 409,
    ApiErrorCodes.sessionFull: 409,
    ApiErrorCodes.duplicateParticipantName: 409,
    ApiErrorCodes.participantNotFound: 404,
    ApiErrorCodes.participantInactive: 403,
    ApiErrorCodes.assignmentUnavailable: 409,
    ApiErrorCodes.credentialsExhausted: 503,
    // Generic
    ApiErrorCodes.validationError: 422,
    ApiErrorCodes.serverMisconfigured: 500,
    ApiErrorCodes.databaseError: 500,
    ApiErrorCodes.invalidDbResponse: 500,
    ApiErrorCodes.internalError: 500,
  };

  group('every known backend code has a mapping', () {
    for (final code in backendCodes.keys) {
      test(code, () => expect(backendCodeMessage(code), isNotNull));
    }

    test('unknown code has no mapping (falls back by failure type)', () {
      expect(backendCodeMessage('SOMETHING_NEW'), isNull);
      expect(commonFailureMessage(failureFor(409, 'SOMETHING_NEW')), isNotEmpty);
    });
  });

  group('no server text is ever displayed', () {
    for (final MapEntry(key: code, value: status) in backendCodes.entries) {
      test(code, () {
        final failure = failureFor(status, code);

        final texts = <String?>[
          commonFailureMessage(failure),
          assignmentFailureMessage(failure),
          joinFailureFeedback(failure).message,
          ...joinFailureFeedback(failure).fieldErrors.values,
          recoverFailureFeedback(failure).message,
          ...recoverFailureFeedback(failure).fieldErrors.values,
        ];

        for (final text in texts.whereType<String>()) {
          expect(text, isNot(contains(serverText)));
          expect(text, isNotEmpty);
        }
      });
    }
  });

  group('participant codes give specific (not generic) text on their screens', () {
    test('join', () {
      expect(joinFailureFeedback(failureFor(409, ApiErrorCodes.sessionFull)).message, contains('full'));
      expect(joinFailureFeedback(failureFor(409, ApiErrorCodes.sessionNotActive)).message, contains('not open'));
      expect(
        joinFailureFeedback(failureFor(409, ApiErrorCodes.duplicateParticipantName)).fieldErrors['participantName'],
        contains('already uses this name'),
      );
      expect(
        joinFailureFeedback(failureFor(404, ApiErrorCodes.sessionNotFound)).fieldErrors['inviteCode'],
        contains('invite code'),
      );
    });

    test('recover', () {
      expect(
        recoverFailureFeedback(failureFor(404, ApiErrorCodes.participantNotFound)).fieldErrors['recoveryCode'],
        contains('recovery code'),
      );
      expect(
        recoverFailureFeedback(failureFor(403, ApiErrorCodes.participantInactive)).message,
        contains('removed'),
      );
      expect(
        recoverFailureFeedback(failureFor(409, ApiErrorCodes.assignmentUnavailable)).message,
        contains("isn't available"),
      );
    });

    test('assignment', () {
      expect(assignmentFailureMessage(failureFor(404, ApiErrorCodes.participantNotFound)), contains('no longer exists'));
      expect(assignmentFailureMessage(failureFor(403, ApiErrorCodes.participantInactive)), contains('removed'));
      expect(assignmentFailureMessage(failureFor(409, ApiErrorCodes.assignmentUnavailable)), contains("isn't available"));
    });

    test('a join code seen on another screen still gets its own text', () {
      // e.g. SESSION_FULL reaching the generic handler.
      expect(commonFailureMessage(failureFor(409, ApiErrorCodes.sessionFull)), contains('full'));
      expect(commonFailureMessage(failureFor(409, ApiErrorCodes.sessionNotDraft)), contains('already been published'));
    });
  });

  test('a bodyless 404 maps to the generic NOT_FOUND text, never a domain message', () {
    final failure = mapErrorResponse(404, '<html>Not Found</html>');
    expect(commonFailureMessage(failure), contains('service could not be found'));
  });
}
