import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/app_session.dart';
import 'package:secret_santa/data/repositories/repository_exceptions.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/assignment/assignment_controller.dart';
import 'package:secret_santa/features/startup/startup_controller.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Storage whose delete fails; reads and writes work.
class _DeleteFailingStorage extends InMemorySecureStorage {
  @override
  Future<void> delete(String key) async => throw SecureStorageException('delete', key, 'locked');
}

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());

  ProviderContainer containerWithListener() {
    final container = env.container();
    container.listen(assignmentControllerProvider, (_, __) {});
    return container;
  }

  test('success loads the assignment with the stored token', () async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    final container = containerWithListener();

    final assignment = await container.read(assignmentControllerProvider.future);

    expect(assignment.giftColor.name, 'GREEN');
    expect(env.client.calls.single.body, {'browserToken': Fixtures.browserToken});
  });

  test('API failure is exposed and the identity is NOT deleted', () async {
    await env.storeParticipant();
    env.client.fail(
      EdgeFunctions.getMyAssignment,
      const NotFoundFailure(code: ApiErrorCodes.participantNotFound, message: 'x', statusCode: 404),
    );
    final container = containerWithListener();

    await expectLater(container.read(assignmentControllerProvider.future), throwsA(isA<NotFoundFailure>()));

    expect(container.read(assignmentControllerProvider).hasError, isTrue);
    expect(await env.store.readParticipant(), isNotNull);
  });

  test('validation failure (stored token rejected) is exposed as an error', () async {
    await env.storeParticipant();
    env.client.fail(
      EdgeFunctions.getMyAssignment,
      const ValidationFailure(code: ApiErrorCodes.validationError, message: 'x', statusCode: 422),
    );
    final container = containerWithListener();

    await expectLater(container.read(assignmentControllerProvider.future), throwsA(isA<ValidationFailure>()));
  });

  test('no stored identity is exposed as NoParticipantIdentityException', () async {
    final container = containerWithListener();

    await expectLater(
      container.read(assignmentControllerProvider.future),
      throwsA(isA<NoParticipantIdentityException>()),
    );
    expect(env.client.calls, isEmpty);
  });

  test('refresh after a network error loads the assignment', () async {
    await env.storeParticipant();
    env.client.fail(
      EdgeFunctions.getMyAssignment,
      const NetworkFailure(code: ApiErrorCodes.networkError, message: 'offline'),
    );
    final container = containerWithListener();
    await expectLater(container.read(assignmentControllerProvider.future), throwsA(isA<NetworkFailure>()));

    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    await container.read(assignmentControllerProvider.notifier).refresh();

    expect(container.read(assignmentControllerProvider).value?.participantName, 'Maria');
  });

  test('a failed refresh keeps the previous assignment available', () async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    final container = containerWithListener();
    await container.read(assignmentControllerProvider.future);

    env.client.fail(
      EdgeFunctions.getMyAssignment,
      const NetworkFailure(code: ApiErrorCodes.networkError, message: 'offline'),
    );
    await container.read(assignmentControllerProvider.notifier).refresh();

    final state = container.read(assignmentControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.value?.participantName, 'Maria');
  });

  test('storedRecoveryCode reads from storage', () async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    final container = containerWithListener();

    expect(
      await container.read(assignmentControllerProvider.notifier).storedRecoveryCode(),
      Fixtures.recoveryCode,
    );
  });

  test('leaveDevice clears the identity and marks the app anonymous without a server call', () async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    final container = containerWithListener();
    await container.read(startupControllerProvider.future);
    await container.read(assignmentControllerProvider.future);
    final callsBefore = env.client.calls.length;

    await container.read(assignmentControllerProvider.notifier).leaveDevice();

    expect(await env.store.readParticipant(), isNull);
    expect(container.read(startupControllerProvider).value, isA<AnonymousSession>());
    expect(env.client.calls.length, callsBefore);
  });

  test('persistence failure on leave keeps the participant state', () async {
    env = TestEnv(storage: _DeleteFailingStorage());
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    final container = containerWithListener();
    await container.read(startupControllerProvider.future);

    await expectLater(
      container.read(assignmentControllerProvider.notifier).leaveDevice(),
      throwsA(isA<SecureStorageException>()),
    );
    expect(container.read(startupControllerProvider).value, isA<ParticipantSession>());
  });
}
