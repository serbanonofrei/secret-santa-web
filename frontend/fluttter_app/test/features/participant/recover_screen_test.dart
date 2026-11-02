import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/recover/recover_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

Finder get codeField => find.byKey(const Key('recoveryCodeField'));

String codeText(WidgetTester tester) => tester.widget<TextField>(codeField).controller!.text;

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());

  testWidgets('auto-formats as XXXX-XXXX-XXXX', (tester) async {
    await pumpScreen(tester, env, const RecoverScreen());

    await tester.enterText(codeField, 'abcdefgh');
    expect(codeText(tester), 'ABCD-EFGH');

    await tester.enterText(codeField, 'abcd efgh jklm extra');
    expect(codeText(tester), 'ABCD-EFGH-JKLM');
  });

  testWidgets('incomplete code shows a field error without calling the API', (tester) async {
    await pumpScreen(tester, env, const RecoverScreen());

    await tester.enterText(codeField, 'ABCD');
    await tester.tap(find.text('Recover'));
    await tester.pump();

    expect(find.textContaining('XXXX-XXXX-XXXX'), findsWidgets);
    expect(env.client.calls, isEmpty);
  });

  testWidgets('PARTICIPANT_NOT_FOUND shows a friendly field error', (tester) async {
    env.client.fail(
      EdgeFunctions.recoverAssignment,
      const NotFoundFailure(code: ApiErrorCodes.participantNotFound, message: 'raw', statusCode: 404),
    );
    await pumpScreen(tester, env, const RecoverScreen());

    await tester.enterText(codeField, Fixtures.recoveryCode);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No participant has this recovery code'), findsOneWidget);
    expect(find.text('raw'), findsNothing);
  });

  testWidgets('PARTICIPANT_INACTIVE shows a banner', (tester) async {
    env.client.fail(
      EdgeFunctions.recoverAssignment,
      const ForbiddenFailure(code: ApiErrorCodes.participantInactive, message: 'raw', statusCode: 403),
    );
    await pumpScreen(tester, env, const RecoverScreen());

    await tester.enterText(codeField, Fixtures.recoveryCode);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('formErrorBanner')), findsOneWidget);
    expect(find.textContaining('removed from the session'), findsOneWidget);
  });

  testWidgets('success stores the identity and disables the form', (tester) async {
    env.client.respond(EdgeFunctions.recoverAssignment, Fixtures.recoverAssignment());
    await pumpScreen(tester, env, const RecoverScreen());

    await tester.enterText(codeField, Fixtures.recoveryCode);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    expect(await env.store.readParticipant(), isNotNull);
    expect(tester.widget<TextField>(codeField).enabled, isFalse);
  });
}
