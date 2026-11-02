import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/app/app.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/services/edge_functions.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Full app (real router + startup controller), fake API, shared storage.
Future<void> launchApp(WidgetTester tester, TestEnv env) async {
  // A new ProviderScope per launch = a fresh app process; only storage survives.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(overrides: env.overrides, child: const SecretSantaApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('join -> save code -> assignment -> relaunch resumes -> leave -> welcome', (tester) async {
    final storage = InMemorySecureStorage();
    final env = TestEnv(storage: storage);
    env.client
      ..respond(EdgeFunctions.joinSession, Fixtures.joinSession())
      ..respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);

    // 1. First launch: anonymous -> welcome.
    await launchApp(tester, env);
    expect(find.text('Join Session'), findsOneWidget);

    // 2. Join.
    await tester.tap(find.text('Join Session'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('inviteCodeField')), Fixtures.inviteCode);
    await tester.enterText(find.byKey(const Key('participantNameField')), 'Maria');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    // 3. Recovery code, then confirm -> assignment.
    expect(find.text(Fixtures.recoveryCode), findsOneWidget);
    await tester.tap(find.text('I saved my recovery code'));
    await tester.pumpAndSettle();
    expect(find.text('Buy a gift for'), findsOneWidget);
    expect(find.text('GREEN'), findsOneWidget);

    // 4. Relaunch: resumes straight on the assignment.
    await launchApp(tester, env);
    expect(find.text('Buy a gift for'), findsOneWidget);
    expect(find.text('Join Session'), findsNothing);

    // 5. Leave this device -> welcome; storage is empty.
    await tester.tap(find.byKey(const Key('assignmentMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmLeaveButton')));
    await tester.pumpAndSettle();
    expect(find.text('Join Session'), findsOneWidget);
    expect(await env.store.readParticipant(), isNull);

    // 6. Relaunch after leaving: stays anonymous.
    await launchApp(tester, env);
    expect(find.text('Join Session'), findsOneWidget);
  });

  testWidgets('recover on another device -> assignment', (tester) async {
    final env = TestEnv();
    env.client
      ..respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment())
      ..respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);

    await launchApp(tester, env);
    await tester.tap(find.text('Recover Assignment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recoveryCodeField')), 'abcdefghjklm');
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    expect(find.text('Buy a gift for'), findsOneWidget);
    expect(env.client.callsTo(EdgeFunctions.recoverAssignment).single.body, {
      'recoveryCode': Fixtures.recoveryCode,
    });
  });
}
