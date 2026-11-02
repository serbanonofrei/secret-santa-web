import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/app/router.dart';
import 'package:secret_santa/data/models/app_session.dart';
import 'package:secret_santa/data/models/participant_identity.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/startup/splash_screen.dart';
import 'package:secret_santa/features/startup/startup_controller.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_app.dart';

/// Startup controller whose result each test controls.
class _FakeStartupController extends StartupController {
  _FakeStartupController(this._result);

  final Future<AppSession> Function() _result;

  @override
  Future<AppSession> build() => _result();
}

Future<ProviderContainer> pumpRouter(
  WidgetTester tester,
  Future<AppSession> Function() result,
) async {
  // Real screens are rendered now, so the data layer needs fakes too.
  final env = TestEnv();
  env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
  final container = ProviderContainer(
    overrides: [
      ...env.overrides,
      startupControllerProvider.overrideWith(() => _FakeStartupController(result)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider)),
      ),
    ),
  );
  return container;
}

String location(ProviderContainer container) =>
    container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('AsyncLoading stays on / with the splash screen', (tester) async {
    final completer = Completer<AppSession>();
    final container = await pumpRouter(tester, () => completer.future);
    await tester.pump();

    expect(location(container), Routes.splash);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const AnonymousSession());
    await tester.pumpAndSettle();
  });

  testWidgets('AsyncError stays on / and shows retry; does not throw', (tester) async {
    final container = await pumpRouter(tester, () async => throw StateError('storage failed'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(location(container), Routes.splash);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('AsyncError blocks navigation away from /', (tester) async {
    final container = await pumpRouter(tester, () async => throw StateError('storage failed'));
    await tester.pumpAndSettle();

    container.read(routerProvider).go(Routes.organizer);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(location(container), Routes.splash);
  });

  testWidgets('AsyncData(AnonymousSession) routes to /welcome', (tester) async {
    final container = await pumpRouter(tester, () async => const AnonymousSession());
    await tester.pumpAndSettle();

    expect(location(container), Routes.welcome);
  });

  testWidgets('AsyncData(ParticipantSession) routes to /assignment', (tester) async {
    final session = ParticipantSession(
      ParticipantCredentials(
        participantId: 'p1',
        browserToken: 'BT_${'x' * 43}',
        savedAt: DateTime.utc(2026, 12, 1),
      ),
    );
    final container = await pumpRouter(tester, () async => session);
    await tester.pumpAndSettle();

    expect(location(container), Routes.assignment);
  });

  group('guards', () {
    final participant = ParticipantSession(
      ParticipantCredentials(
        participantId: 'p1',
        browserToken: 'BT_${'x' * 43}',
        savedAt: DateTime.utc(2026, 12, 1),
      ),
    );

    for (final route in [Routes.welcome, Routes.join, Routes.joinRecoveryCode, Routes.recover]) {
      testWidgets('participant opening $route is redirected to /assignment', (tester) async {
        final container = await pumpRouter(tester, () async => participant);
        await tester.pumpAndSettle();

        container.read(routerProvider).go(route);
        await tester.pumpAndSettle();

        expect(location(container), Routes.assignment);
      });
    }

    testWidgets('anonymous opening /assignment is redirected to /welcome', (tester) async {
      final container = await pumpRouter(tester, () async => const AnonymousSession());
      await tester.pumpAndSettle();

      container.read(routerProvider).go(Routes.assignment);
      await tester.pumpAndSettle();

      expect(location(container), Routes.welcome);
    });

    testWidgets('anonymous can open /join and /recover', (tester) async {
      final container = await pumpRouter(tester, () async => const AnonymousSession());
      await tester.pumpAndSettle();

      for (final route in [Routes.join, Routes.recover]) {
        container.read(routerProvider).go(route);
        await tester.pumpAndSettle();
        expect(location(container), route);
      }
    });

    testWidgets('/organizer is reachable for both participant and anonymous', (tester) async {
      final container = await pumpRouter(tester, () async => participant);
      await tester.pumpAndSettle();

      container.read(routerProvider).go(Routes.organizer);
      await tester.pumpAndSettle();

      expect(location(container), Routes.organizer);
    });

    testWidgets('becoming anonymous on /assignment moves to /welcome', (tester) async {
      final container = await pumpRouter(tester, () async => participant);
      await tester.pumpAndSettle();
      expect(location(container), Routes.assignment);

      container.read(startupControllerProvider.notifier).markAnonymous();
      await tester.pumpAndSettle();

      expect(location(container), Routes.welcome);
    });
  });
}
