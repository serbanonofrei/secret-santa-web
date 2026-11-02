import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/app/router.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/join/join_controller.dart';
import 'package:secret_santa/features/participant/join/join_screen.dart';
import 'package:secret_santa/features/participant/join/recovery_code_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Real router + real startup/join controllers in a fresh container, i.e. a
/// fresh app process (what a browser refresh or hot restart produces).
Future<ProviderContainer> launch(WidgetTester tester, TestEnv env, {String? initialLocation}) async {
  final container = env.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider))),
    ),
  );
  if (initialLocation != null) container.read(routerProvider).go(initialLocation);
  await tester.pumpAndSettle();
  return container;
}

String path(ProviderContainer c) => c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

Future<void> joinAsMaria(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('inviteCodeField')), Fixtures.inviteCode);
  await tester.enterText(find.byKey(const Key('participantNameField')), 'Maria');
  await tester.tap(find.text('Join'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('direct navigation to /join/recovery-code redirects to /join', (tester) async {
    final env = TestEnv();
    final container = await launch(tester, env, initialLocation: Routes.joinRecoveryCode);

    expect(path(container), Routes.join);
    expect(find.byType(JoinScreen), findsOneWidget);
    expect(find.byType(RecoveryCodeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deep link while startup is loading still ends on /join, never on an empty code screen',
      (tester) async {
    // The router starts at "/", the deep link arrives before startup settles.
    final env = TestEnv();
    final container = env.container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider))),
      ),
    );
    container.read(routerProvider).go(Routes.joinRecoveryCode);
    await tester.pumpAndSettle();

    expect(path(container), Routes.join);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh on the recovery code screen: fresh process -> /assignment (identity was saved)',
      (tester) async {
    final env = TestEnv();
    env.client
      ..respond(EdgeFunctions.joinSession, Fixtures.joinSession())
      ..respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);

    final first = await launch(tester, env, initialLocation: Routes.join);
    await joinAsMaria(tester);
    expect(path(first), Routes.joinRecoveryCode);

    // Browser refresh / hot restart: new container, same storage, same URL.
    await tester.pumpWidget(const SizedBox());
    final second = await launch(tester, env, initialLocation: Routes.joinRecoveryCode);

    // The join was saved, so the device is a participant now.
    expect(path(second), Routes.assignment);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh on the recovery code screen when the save had failed -> /join, no crash',
      (tester) async {
    final env = TestEnv(storage: FlakyWriteStorage());
    env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());

    await launch(tester, env, initialLocation: Routes.join);
    await joinAsMaria(tester);
    expect(find.byKey(const Key('notSavedWarning')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final second = await launch(tester, env, initialLocation: Routes.joinRecoveryCode);

    expect(path(second), Routes.join);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing controller state while on the screen: guard moves to /join, no crash', (tester) async {
    final env = TestEnv(storage: FlakyWriteStorage());
    env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());

    final container = await launch(tester, env, initialLocation: Routes.join);
    await joinAsMaria(tester);
    expect(path(container), Routes.joinRecoveryCode);

    // Simulate the controller losing its state (e.g. provider invalidated).
    container.invalidate(joinControllerProvider);
    await tester.pumpAndSettle();

    expect(path(container), Routes.join);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser back from the code screen is sent back to the code (cannot skip confirming)',
      (tester) async {
    final env = TestEnv();
    env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());

    final container = await launch(tester, env, initialLocation: Routes.join);
    await joinAsMaria(tester);

    container.read(routerProvider).go(Routes.join);
    await tester.pumpAndSettle();

    expect(path(container), Routes.joinRecoveryCode);
    expect(find.text(Fixtures.recoveryCode), findsOneWidget);
  });
}
