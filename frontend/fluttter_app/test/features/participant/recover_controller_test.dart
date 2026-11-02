import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/models/app_session.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/recover/recover_controller.dart';
import 'package:secret_santa/features/startup/startup_controller.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());

  /// Keeps the auto-dispose controller alive for the duration of a test.
  RecoverController controllerOf(ProviderContainer container) {
    container.listen(recoverControllerProvider, (_, __) {});
    return container.read(recoverControllerProvider.notifier);
  }

  test('success formats the code, stores the identity and switches startup to participant', () async {
    env.client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());
    final container = env.container();
    await container.read(startupControllerProvider.future);

    await controllerOf(container).submit('abcd efgh jklm');

    expect(env.client.calls.single.body, {'recoveryCode': Fixtures.recoveryCode});
    expect(container.read(recoverControllerProvider), isA<RecoverSucceeded>());
    expect((await env.store.readParticipant())?.browserToken, Fixtures.browserToken);
    expect(container.read(startupControllerProvider).value, isA<ParticipantSession>());
  });

  test('validation failure blocks the request', () async {
    final container = env.container();

    await controllerOf(container).submit('ABCD-EF');

    final state = container.read(recoverControllerProvider) as RecoverFailed;
    expect(state.feedback.fieldErrors['recoveryCode'], isNotNull);
    expect(env.client.calls, isEmpty);
  });

  test('PARTICIPANT_NOT_FOUND is a field error', () async {
    env.client.fail(
      EdgeFunctions.recoverAssignment,
      const NotFoundFailure(code: ApiErrorCodes.participantNotFound, message: 'x', statusCode: 404),
    );
    final container = env.container();

    await controllerOf(container).submit(Fixtures.recoveryCode);

    final state = container.read(recoverControllerProvider) as RecoverFailed;
    expect(state.feedback.fieldErrors['recoveryCode'], isNotNull);
    expect(await env.store.readParticipant(), isNull);
  });

  test('PARTICIPANT_INACTIVE is a banner message', () async {
    env.client.fail(
      EdgeFunctions.recoverAssignment,
      const ForbiddenFailure(code: ApiErrorCodes.participantInactive, message: 'x', statusCode: 403),
    );
    final container = env.container();

    await controllerOf(container).submit(Fixtures.recoveryCode);

    final state = container.read(recoverControllerProvider) as RecoverFailed;
    expect(state.feedback.message, isNotNull);
    expect(state.feedback.fieldErrors, isEmpty);
  });

  test('persistence failure is retryable and leaves startup anonymous', () async {
    final flaky = FlakyWriteStorage();
    env = TestEnv(storage: flaky);
    env.client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());
    final container = env.container();
    await container.read(startupControllerProvider.future);
    final controller = controllerOf(container);

    await controller.submit(Fixtures.recoveryCode);
    expect(container.read(recoverControllerProvider), isA<RecoverFailed>());
    expect(container.read(startupControllerProvider).value, isA<AnonymousSession>());

    flaky.failWrites = false;
    await controller.submit(Fixtures.recoveryCode);
    expect(container.read(recoverControllerProvider), isA<RecoverSucceeded>());
    expect(container.read(startupControllerProvider).value, isA<ParticipantSession>());
  });
}
