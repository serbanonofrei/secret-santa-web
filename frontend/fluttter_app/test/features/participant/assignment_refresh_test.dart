import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/data_providers.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/data/services/participant_service.dart';
import 'package:secret_santa/features/participant/assignment/assignment_controller.dart';
import 'package:secret_santa/features/participant/assignment/assignment_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// API client whose get-my-assignment calls block until released.
class _GatedApiClient extends FakeApiClient {
  final List<Completer<void>> gates = [];
  bool gate = false;

  @override
  Future<Map<String, dynamic>> post(
    String functionName, {
    Map<String, Object?> body = const {},
    CancelToken? cancelToken,
  }) async {
    if (gate && functionName == EdgeFunctions.getMyAssignment) {
      final completer = Completer<void>();
      gates.add(completer);
      await completer.future;
    }
    return super.post(functionName, body: body, cancelToken: cancelToken);
  }

  void releaseAll() {
    for (final g in gates) {
      if (!g.isCompleted) g.complete();
    }
  }
}

void main() {
  late TestEnv env;
  late _GatedApiClient client;

  List<Override> overrides() => [
        ...env.overrides,
        participantServiceProvider.overrideWithValue(ParticipantService(client)),
      ];

  setUp(() async {
    env = TestEnv();
    client = _GatedApiClient();
    await env.storeParticipant();
    client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    c.listen(assignmentControllerProvider, (_, __) {});
    return c;
  }

  group('controller', () {
    test('existing assignment stays available while refresh runs', () async {
      final c = container();
      await c.read(assignmentControllerProvider.future);

      client.gate = true;
      final refresh = c.read(assignmentControllerProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);

      final during = c.read(assignmentControllerProvider);
      expect(during.isLoading, isTrue);
      expect(during.value?.participantName, 'Maria');

      client.releaseAll();
      await refresh;
    });

    test('duplicate refresh calls share one request', () async {
      final c = container();
      await c.read(assignmentControllerProvider.future);
      final before = client.callsTo(EdgeFunctions.getMyAssignment).length;

      client.gate = true;
      final notifier = c.read(assignmentControllerProvider.notifier);
      final a = notifier.refresh();
      final b = notifier.refresh();
      final d = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      client.releaseAll();
      await Future.wait([a, b, d]);

      expect(client.callsTo(EdgeFunctions.getMyAssignment).length - before, 1);
    });

    test('refresh during the initial load does not start a second request', () async {
      client.gate = true;
      final c = container();
      await Future<void>.delayed(Duration.zero);

      final refresh = c.read(assignmentControllerProvider.notifier).refresh();
      client.releaseAll();
      await refresh;
      await c.read(assignmentControllerProvider.future);

      expect(client.callsTo(EdgeFunctions.getMyAssignment), hasLength(1));
    });

    test('refresh failure keeps the displayed data and exposes the error', () async {
      final c = container();
      await c.read(assignmentControllerProvider.future);

      client.fail(
        EdgeFunctions.getMyAssignment,
        const NetworkFailure(code: ApiErrorCodes.networkError, message: 'offline'),
      );
      await c.read(assignmentControllerProvider.notifier).refresh();

      final state = c.read(assignmentControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.value?.participantName, 'Maria');
    });

    test('a new refresh can start after a failed one', () async {
      final c = container();
      await c.read(assignmentControllerProvider.future);
      client.fail(
        EdgeFunctions.getMyAssignment,
        const NetworkFailure(code: ApiErrorCodes.networkError, message: 'offline'),
      );
      await c.read(assignmentControllerProvider.notifier).refresh();

      client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
      await c.read(assignmentControllerProvider.notifier).refresh();

      expect(c.read(assignmentControllerProvider).hasError, isFalse);
    });

    test('disposing during a refresh does not throw', () async {
      final c = ProviderContainer(overrides: overrides());
      final sub = c.listen(assignmentControllerProvider, (_, __) {});
      await c.read(assignmentControllerProvider.future);

      client.gate = true;
      final refresh = c.read(assignmentControllerProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);
      sub.close();
      c.dispose();
      client.releaseAll();

      await expectLater(refresh, completes);
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides(), child: const MaterialApp(home: AssignmentScreen())),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('refresh failure keeps the colors visible and shows a temporary message', (tester) async {
      await pump(tester);
      expect(find.text('GREEN'), findsOneWidget);

      client.fail(
        EdgeFunctions.getMyAssignment,
        const NetworkFailure(code: ApiErrorCodes.networkError, message: 'RAW SERVER TEXT'),
      );
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('GREEN'), findsOneWidget);
      expect(find.byKey(const Key('refreshErrorSnackBar')), findsOneWidget);
      expect(find.textContaining('RAW SERVER TEXT'), findsNothing);
      expect(find.text('Try again'), findsNothing); // not the full-screen error view
    });

    testWidgets('refresh button is disabled while refreshing', (tester) async {
      await pump(tester);

      client.gate = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();

      final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh));
      expect(button.onPressed, isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      client.releaseAll();
      await tester.pumpAndSettle();
    });
  });
}
