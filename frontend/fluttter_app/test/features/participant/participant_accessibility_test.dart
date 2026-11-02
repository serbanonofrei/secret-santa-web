import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/core/network/api_failure.dart';
import 'package:secret_santa/data/models/color_info.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/join/join_screen.dart';
import 'package:secret_santa/features/participant/recover/recover_screen.dart';
import 'package:secret_santa/shared/widgets/color_swatch_card.dart';
import 'package:secret_santa/shared/widgets/recovery_code_display.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('field errors are part of the field semantics (associated with the input)', (tester) async {
    final env = TestEnv();
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, env, const JoinScreen());

    await tester.tap(find.text('Join'));
    await tester.pump();

    // InputDecoration.errorText is exposed on the text field node itself.
    final node = tester.getSemantics(find.byKey(const Key('participantNameField')));
    expect(node.label + node.value + node.hint, contains('Enter your name.'));
    handle.dispose();
  });

  testWidgets('the error banner is announced with an "Error:" prefix', (tester) async {
    final env = TestEnv();
    env.client.fail(
      EdgeFunctions.recoverAssignment,
      const ForbiddenFailure(code: ApiErrorCodes.participantInactive, message: 'x', statusCode: 403),
    );
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, env, const RecoverScreen());

    await tester.enterText(find.byKey(const Key('recoveryCodeField')), Fixtures.recoveryCode);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('^Error: .*removed')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the recovery code is read character by character with "dash"', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RecoveryCodeDisplay(code: 'AB2C-DEFG-HJKL'))),
    );

    expect(find.bySemanticsLabel('Recovery code: A B 2 C dash D E F G dash H J K L'), findsOneWidget);
    expect(find.bySemanticsLabel('Copy recovery code'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('color cards expose label, name and hex as one announcement', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ColorSwatchCard(label: 'Your color', color: ColorInfo(name: 'WHITE', hexColor: '#FFFFFF')),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Your color: WHITE, #FFFFFF'), findsOneWidget);
    // Name and hex are also visible text, not color alone.
    expect(find.text('WHITE'), findsOneWidget);
    expect(find.text('#FFFFFF'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an invalid hex value still renders name and hex, no crash', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ColorSwatchCard(label: 'Your color', color: ColorInfo(name: 'ODD', hexColor: 'nope'))),
      ),
    );

    expect(find.text('ODD'), findsOneWidget);
    expect(find.text('nope'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('Tab moves through the join form in reading order (web keyboard)', (tester) async {
    final env = TestEnv();
    await pumpScreen(tester, env, const JoinScreen());
    await tester.pumpAndSettle();

    // Invite code field has autofocus when empty.
    EditableText focused() => tester.widget<EditableText>(
          find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
        );
    final inviteController = tester.widget<TextField>(find.byKey(const Key('inviteCodeField'))).controller;
    final nameController = tester.widget<TextField>(find.byKey(const Key('participantNameField'))).controller;

    expect(focused().controller, inviteController);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused().controller, nameController);
  });
}
