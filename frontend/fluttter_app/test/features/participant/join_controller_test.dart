import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/app_session.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/join/join_controller.dart';
import 'package:secret_santa/features/startup/startup_controller.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());

  group('success', () {
    test('normalizes input, joins and stores the identity', () async {
      env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final container = env.container();

      await container.read(joinControllerProvider.notifier).submit(
            inviteCode: ' abc 234 ',
            participantName: '  Maria   Lopez ',
          );

      final state = container.read(joinControllerProvider);
      expect(state, isA<JoinSucceeded>());
      expect((state as JoinSucceeded).savedOnDevice, isTrue);
      expect(state.outcome.recoveryCode, Fixtures.recoveryCode);
      expect(env.client.calls.single.body, {'inviteCode': 'ABC234', 'participantName': 'Maria Lopez'});
      expect(await env.store.readParticipant(), isNotNull);
    });

    test('startup stays anonymous until the code is confirmed', () async {
      env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final container = env.container();
      await container.read(startupControllerProvider.future);

      final controller = container.read(joinControllerProvider.notifier);
      await controller.submit(inviteCode: Fixtures.inviteCode, participantName: 'Maria');
      expect(container.read(startupControllerProvider).value, isA<AnonymousSession>());

      await controller.confirmRecoveryCodeSaved();

      expect(container.read(startupControllerProvider).value, isA<ParticipantSession>());
      expect(container.read(joinControllerProvider), isA<JoinIdle>());
    });
  });

  group('validation failure', () {
    test('local validation blocks the request', () async {
      final container = env.container();

      await container.read(joinControllerProvider.notifier).submit(inviteCode: 'AB', participantName: '   ');

      final state = container.read(joinControllerProvider) as JoinFailed;
      expect(state.feedback.fieldErrors.keys, containsAll(['inviteCode', 'participantName']));
      expect(env.client.calls, isEmpty);
    });

    test('server ValidationFailure maps to field errors without server text', () async {
      env.client.fail(
        EdgeFunctions.joinSession,
        const ValidationFailure(
          code: ApiErrorCodes.validationError,
          message: 'Request validation failed',
          statusCode: 422,
          fieldErrors: [FieldError(field: 'participantName', message: 'SERVER TEXT')],
        ),
      );
      final container = env.container();

      await container.read(joinControllerProvider.notifier).submit(
            inviteCode: Fixtures.inviteCode,
            participantName: 'Maria',
          );

      final state = container.read(joinControllerProvider) as JoinFailed;
      expect(state.feedback.fieldErrors['participantName'], isNotNull);
      expect(state.feedback.fieldErrors['participantName'], isNot(contains('SERVER TEXT')));
    });

    test('editing a field clears its error', () async {
      final container = env.container();
      final controller = container.read(joinControllerProvider.notifier);
      await controller.submit(inviteCode: 'AB', participantName: 'Maria');

      controller.clearFieldError('inviteCode');

      expect(container.read(joinControllerProvider), isA<JoinIdle>());
    });
  });

  group('API failure', () {
    final cases = <String, (ApiFailure, String?, bool)>{
      // failure, expected field (null = banner), expect message
      'SESSION_NOT_FOUND': (
        const NotFoundFailure(code: ApiErrorCodes.sessionNotFound, message: 'x', statusCode: 404),
        'inviteCode',
        false,
      ),
      'DUPLICATE_PARTICIPANT_NAME': (
        const ConflictFailure(code: ApiErrorCodes.duplicateParticipantName, message: 'x', statusCode: 409),
        'participantName',
        false,
      ),
      'SESSION_FULL': (
        const ConflictFailure(code: ApiErrorCodes.sessionFull, message: 'x', statusCode: 409),
        null,
        true,
      ),
      'SESSION_NOT_ACTIVE': (
        const ConflictFailure(code: ApiErrorCodes.sessionNotActive, message: 'x', statusCode: 409),
        null,
        true,
      ),
      'network': (
        const NetworkFailure(code: ApiErrorCodes.networkError, message: 'x'),
        null,
        true,
      ),
    };

    for (final MapEntry(key: name, value: (failure, field, expectBanner)) in cases.entries) {
      test('$name shows a friendly message and stores nothing', () async {
        env.client.fail(EdgeFunctions.joinSession, failure);
        final container = env.container();

        await container.read(joinControllerProvider.notifier).submit(
              inviteCode: Fixtures.inviteCode,
              participantName: 'Maria',
            );

        final state = container.read(joinControllerProvider) as JoinFailed;
        if (field != null) expect(state.feedback.fieldErrors[field], isNotNull);
        expect(state.feedback.message != null, expectBanner);
        expect(await env.store.readParticipant(), isNull);
      });
    }
  });

  group('persistence failure', () {
    test('ParticipantNotSavedException still succeeds with savedOnDevice=false', () async {
      final flaky = FlakyWriteStorage();
      env = TestEnv(storage: flaky);
      env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final container = env.container();
      await container.read(startupControllerProvider.future);

      final controller = container.read(joinControllerProvider.notifier);
      await controller.submit(inviteCode: Fixtures.inviteCode, participantName: 'Maria');

      final state = container.read(joinControllerProvider) as JoinSucceeded;
      expect(state.savedOnDevice, isFalse);
      expect(state.outcome.recoveryCode, Fixtures.recoveryCode);

      // Confirming does not pretend the identity is on the device.
      await controller.confirmRecoveryCodeSaved();
      expect(container.read(startupControllerProvider).value, isA<AnonymousSession>());
      expect(container.read(joinControllerProvider), isA<JoinFinishedUnsaved>());
      expect(env.client.callsTo(EdgeFunctions.joinSession), hasLength(1));

      // The next visit to /join starts clean.
      controller.reset();
      expect(container.read(joinControllerProvider), isA<JoinIdle>());
    });
  });

  group('confirm hardening', () {
    test('storage read failure on confirm keeps the join pending (code not lost)', () async {
      final storage = _ReadSwitchStorage();
      env = TestEnv(storage: storage);
      env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final container = env.container();
      await container.read(startupControllerProvider.future);
      final controller = container.read(joinControllerProvider.notifier);
      await controller.submit(inviteCode: Fixtures.inviteCode, participantName: 'Maria');

      storage.failReads = true;
      await controller.confirmRecoveryCodeSaved();

      expect(container.read(startupControllerProvider).hasError, isTrue);
      expect(container.read(joinControllerProvider), isA<JoinSucceeded>());

      // Storage recovers: the splash retry promotes the participant, and the
      // join flow closes itself (no stale pending join left behind).
      storage.failReads = false;
      await container.read(startupControllerProvider.notifier).retry();

      expect(container.read(startupControllerProvider).value, isA<ParticipantSession>());
      expect(container.read(joinControllerProvider), isA<JoinIdle>());
    });

    test('confirm twice quickly: one sync result, flow closed once', () async {
      env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final container = env.container();
      await container.read(startupControllerProvider.future);
      final controller = container.read(joinControllerProvider.notifier);
      await controller.submit(inviteCode: Fixtures.inviteCode, participantName: 'Maria');

      await Future.wait([controller.confirmRecoveryCodeSaved(), controller.confirmRecoveryCodeSaved()]);

      expect(container.read(startupControllerProvider).value, isA<ParticipantSession>());
      expect(container.read(joinControllerProvider), isA<JoinIdle>());
    });

    test('reset never discards a pending join', () async {
      env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final container = env.container();
      final controller = container.read(joinControllerProvider.notifier);
      await controller.submit(inviteCode: Fixtures.inviteCode, participantName: 'Maria');

      controller.reset();

      expect(container.read(joinControllerProvider), isA<JoinSucceeded>());
    });

    test('submitting while already submitting does not call the API twice', () async {
      env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
      final container = env.container();
      final controller = container.read(joinControllerProvider.notifier);

      await Future.wait([
        controller.submit(inviteCode: Fixtures.inviteCode, participantName: 'Maria'),
        controller.submit(inviteCode: Fixtures.inviteCode, participantName: 'Maria'),
      ]);

      expect(env.client.callsTo(EdgeFunctions.joinSession), hasLength(1));
    });
  });
}

/// In-memory storage whose reads fail on demand (writes keep working).
class _ReadSwitchStorage extends InMemorySecureStorage {
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw SecureStorageException('read', key, 'locked');
    return super.read(key);
  }
}
