import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/app/app.dart';
import 'package:secret_santa/core/storage/secure_storage.dart';
import 'package:secret_santa/data/models/color_info.dart';
import 'package:secret_santa/data/models/view_models.dart';
import 'package:secret_santa/data/services/edge_functions.dart';
import 'package:secret_santa/features/participant/join/join_controller.dart';

import '../../helpers/fakes.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// All visible text on screen.
Iterable<String> visibleText(WidgetTester tester) sync* {
  for (final widget in tester.allWidgets) {
    if (widget is Text) yield widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (widget is SelectableText) yield widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (widget is EditableText) yield widget.controller.text;
  }
}

void main() {
  testWidgets('the browser token never appears on any participant screen', (tester) async {
    final env = TestEnv(storage: InMemorySecureStorage());
    env.client
      ..respond(EdgeFunctions.joinSession, Fixtures.joinSession())
      ..respond(EdgeFunctions.getMyAssignment, Fixtures.getMyAssignment);

    await tester.pumpWidget(ProviderScope(overrides: env.overrides, child: const SecretSantaApp()));
    await tester.pumpAndSettle();
    final seen = <String>[...visibleText(tester)];

    await tester.tap(find.text('Join Session'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('inviteCodeField')), Fixtures.inviteCode);
    await tester.enterText(find.byKey(const Key('participantNameField')), 'Maria');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    seen.addAll(visibleText(tester)); // recovery code screen

    await tester.tap(find.text('I saved my recovery code'));
    await tester.pumpAndSettle();
    seen.addAll(visibleText(tester)); // assignment

    await tester.tap(find.byKey(const Key('assignmentMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Recovery Code'));
    await tester.pumpAndSettle();
    seen.addAll(visibleText(tester)); // recovery code dialog

    for (final text in seen) {
      expect(text, isNot(contains(Fixtures.browserToken)));
      expect(text, isNot(contains(Fixtures.organizerToken)));
    }
  });

  test('UI-facing join state toString never contains the recovery code', () {
    const outcome = JoinOutcome(
      participantId: Fixtures.participantId,
      recoveryCode: Fixtures.recoveryCode,
      myColor: ColorInfo(name: 'RED', hexColor: '#FF0000'),
      giftColor: ColorInfo(name: 'GREEN', hexColor: '#00FF00'),
    );
    const state = JoinSucceeded(outcome: outcome, savedOnDevice: false);

    expect(outcome.toString(), isNot(contains(Fixtures.recoveryCode)));
    expect(state.toString(), isNot(contains(Fixtures.recoveryCode)));
  });

  test('persistence exception from a failed join save does not leak the token or code', () async {
    final env = TestEnv(storage: FlakyWriteStorage());
    env.client.respond(EdgeFunctions.joinSession, Fixtures.joinSession());
    final container = env.container();

    await container.read(joinControllerProvider.notifier).submit(
          inviteCode: Fixtures.inviteCode,
          participantName: 'Maria',
        );

    final text = container.read(joinControllerProvider).toString();
    expect(text, isNot(contains(Fixtures.browserToken)));
    expect(text, isNot(contains(Fixtures.recoveryCode)));
  });
}
