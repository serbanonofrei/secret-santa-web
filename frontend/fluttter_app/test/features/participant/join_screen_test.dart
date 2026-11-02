import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/app/router.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/join/join_screen.dart';
import 'package:secret_santa/features/welcome/welcome_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Real router (navigation after join is done by its guard), opened on /join.
Future<void> pumpJoinFlow(WidgetTester tester, TestEnv env) async {
  final container = env.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider))),
    ),
  );
  container.read(routerProvider).go(Routes.join);
  await tester.pumpAndSettle();
  expect(find.byType(JoinScreen), findsOneWidget);
}

Finder get inviteField => find.byKey(const Key('inviteCodeField'));
Finder get nameField => find.byKey(const Key('participantNameField'));

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());

  testWidgets('invite code is upper-cased and limited to 6 characters', (tester) async {
    await pumpJoinFlow(tester, env);

    await tester.enterText(inviteField, 'abc2345xyz');

    expect(tester.widget<TextField>(inviteField).controller!.text, 'ABC234');
  });

  testWidgets('empty name shows a field error without calling the API', (tester) async {
    await pumpJoinFlow(tester, env);

    await tester.enterText(inviteField, Fixtures.inviteCode);
    await tester.tap(find.text('Join'));
    await tester.pump();

    expect(find.text('Enter your name.'), findsOneWidget);
    expect(env.client.calls, isEmpty);
  });

  testWidgets('duplicate name shows the friendly message under the name field', (tester) async {
    env.client.fail(
      EdgeFunctions.joinSession,
      const ConflictFailure(code: ApiErrorCodes.duplicateParticipantName, message: 'raw', statusCode: 409),
    );
    await pumpJoinFlow(tester, env);

    await tester.enterText(inviteField, Fixtures.inviteCode);
    await tester.enterText(nameField, 'Maria');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already uses this name'), findsOneWidget);
    expect(find.text('raw'), findsNothing);
  });

  testWidgets('session full shows a banner', (tester) async {
    env.client.fail(
      EdgeFunctions.joinSession,
      const ConflictFailure(code: ApiErrorCodes.sessionFull, message: 'raw', statusCode: 409),
    );
    await pumpJoinFlow(tester, env);

    await tester.enterText(inviteField, Fixtures.inviteCode);
    await tester.enterText(nameField, 'Maria');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('formErrorBanner')), findsOneWidget);
    expect(find.textContaining('This session is full'), findsOneWidget);
  });

  testWidgets('success navigates to the recovery code screen', (tester) async {
    env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
    await pumpJoinFlow(tester, env);

    await tester.enterText(inviteField, Fixtures.inviteCode);
    await tester.enterText(nameField, 'Maria');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.text(Fixtures.recoveryCode), findsOneWidget);
    expect(find.text('I saved my recovery code'), findsOneWidget);
    expect(find.byKey(const Key('notSavedWarning')), findsNothing);
  });

  testWidgets('persistence failure still shows the code, the warning and the participant id', (tester) async {
    env = TestEnv(storage: FlakyWriteStorage());
    env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
    await pumpJoinFlow(tester, env);

    await tester.enterText(inviteField, Fixtures.inviteCode);
    await tester.enterText(nameField, 'Maria');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.text(Fixtures.recoveryCode), findsOneWidget);
    expect(find.byKey(const Key('notSavedWarning')), findsOneWidget);
    expect(find.textContaining(Fixtures.participantId), findsOneWidget);
    expect(find.textContaining('try again', findRichText: true), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(JoinScreen), findsNothing);
    expect(env.client.callsTo(EdgeFunctions.joinSession), hasLength(1));
  });
}
