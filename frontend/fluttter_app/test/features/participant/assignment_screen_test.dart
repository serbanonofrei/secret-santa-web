import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/assignment/assignment_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());

  testWidgets('shows both colors with name and hex, not color alone', (tester) async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);

    await pumpScreen(tester, env, const AssignmentScreen());
    await tester.pumpAndSettle();

    expect(find.text('Your color'), findsOneWidget);
    expect(find.text('Buy a gift for'), findsOneWidget);
    expect(find.text('RED'), findsOneWidget);
    expect(find.text('#FF0000'), findsOneWidget);
    expect(find.text('GREEN'), findsOneWidget);
    expect(find.text('#00FF00'), findsOneWidget);
    expect(find.bySemanticsLabel('Buy a gift for: GREEN, #00FF00'), findsOneWidget);
  });

  testWidgets('refresh calls the API again', (tester) async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    await pumpScreen(tester, env, const AssignmentScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(env.client.callsTo(EdgeFunctions.getMyAssignment), hasLength(2));
  });

  testWidgets('Show Recovery Code displays the stored code', (tester) async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    await pumpScreen(tester, env, const AssignmentScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assignmentMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Recovery Code'));
    await tester.pumpAndSettle();

    expect(find.text(Fixtures.recoveryCode), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('Leave This Device asks for confirmation, then clears the identity', (tester) async {
    await env.storeParticipant();
    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    await pumpScreen(tester, env, const AssignmentScreen());
    await tester.pumpAndSettle();
    final callsBefore = env.client.calls.length;

    await tester.tap(find.byKey(const Key('assignmentMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave This Device'));
    await tester.pumpAndSettle();

    expect(find.textContaining('removes your local identity from this device'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await env.store.readParticipant(), isNotNull);

    await tester.tap(find.byKey(const Key('assignmentMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmLeaveButton')));
    await tester.pumpAndSettle();

    expect(await env.store.readParticipant(), isNull);
    expect(env.client.calls.length, callsBefore);
  });

  testWidgets('identity rejected (404) offers Leave instead of Try again', (tester) async {
    await env.storeParticipant();
    env.client.fail(
      EdgeFunctions.getMyAssignment,
      const NotFoundFailure(code: ApiErrorCodes.participantNotFound, message: 'raw', statusCode: 404),
    );
    await pumpScreen(tester, env, const AssignmentScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('no longer exists'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Leave This Device'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('network error offers Try again', (tester) async {
    await env.storeParticipant();
    env.client.fail(
      EdgeFunctions.getMyAssignment,
      const NetworkFailure(code: ApiErrorCodes.networkError, message: 'raw'),
    );
    await pumpScreen(tester, env, const AssignmentScreen());
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);

    env.client.respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('GREEN'), findsOneWidget);
  });
}
