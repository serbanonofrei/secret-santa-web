import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_santa/app/route_guard.dart';
import 'package:secret_santa/app/routes.dart';
import 'package:secret_santa/data/models/app_session.dart';
import 'package:secret_santa/data/models/participant_identity.dart';

final participant = ParticipantSession(
  ParticipantCredentials(participantId: 'p1', browserToken: 'BT_x', savedAt: DateTime.utc(2026, 12, 1)),
);
const anonymous = AnonymousSession();

/// Every startup state the redirect can see, including the tricky ones.
final startupStates = <String, AsyncValue<AppSession>>{
  'loading': const AsyncLoading<AppSession>(),
  'error': AsyncError<AppSession>(StateError('storage'), StackTrace.empty),
  'refreshing-over-participant': const AsyncLoading<AppSession>().copyWithPrevious(AsyncData(participant)),
  'error-over-participant':
      AsyncError<AppSession>(StateError('storage'), StackTrace.empty).copyWithPrevious(AsyncData(participant)),
  'anonymous': const AsyncData<AppSession>(anonymous),
  'participant': AsyncData<AppSession>(participant),
};

final locations = [
  Routes.splash,
  Routes.welcome,
  Routes.join,
  '${Routes.join}?code=ABC234',
  Routes.joinRecoveryCode,
  Routes.recover,
  Routes.assignment,
  Routes.organizer,
  '/does-not-exist',
  '/?from=%2Fassignment',
  '/?from=%2Fjoin%3Fcode%3DABC234',
  '/?from=https%3A%2F%2Fevil.example',
  '/?from=%2F%2Fevil.example',
  '/?from=%2F',
];

/// Follows redirects like GoRouter does. Fails on a loop or a long chain.
String settle(AsyncValue<AppSession> startup, JoinFlowStatus join, String start) {
  final visited = <String>{start};
  var location = start;
  for (var i = 0; i < 5; i++) {
    final next = resolveRedirect(startup: startup, join: join, uri: Uri.parse(location));
    if (next == null) return location;
    if (!visited.add(next)) fail('redirect loop: ${[...visited, next].join(' -> ')}');
    location = next;
  }
  fail('redirect chain too long from $start: ${visited.join(' -> ')}');
}

void main() {
  group('no redirect loops (every state x join status x location)', () {
    for (final MapEntry(key: name, value: startup) in startupStates.entries) {
      for (final join in JoinFlowStatus.values) {
        for (final location in locations) {
          test('$name / ${join.name} / $location', () {
            final end = settle(startup, join, location);
            expect(Uri.parse(end).path, isNot('/does-not-exist'));
          });
        }
      }
    }
  });

  group('unsettled startup', () {
    for (final name in ['loading', 'error', 'refreshing-over-participant', 'error-over-participant']) {
      test('$name holds every route on / and remembers the target', () {
        final startup = startupStates[name]!;
        expect(settle(startup, JoinFlowStatus.none, Routes.assignment), '/?from=%2Fassignment');
        expect(settle(startup, JoinFlowStatus.none, Routes.splash), Routes.splash);
      });
    }
  });

  group('deep links survive the splash screen', () {
    test('anonymous invite link keeps its query', () {
      expect(
        settle(startupStates['anonymous']!, JoinFlowStatus.none, '/?from=%2Fjoin%3Fcode%3DABC234'),
        '/join?code=ABC234',
      );
    });

    test('remembered target still goes through the guards', () {
      expect(
        settle(startupStates['participant']!, JoinFlowStatus.none, '/?from=%2Fjoin%3Fcode%3DABC234'),
        Routes.assignment,
      );
      expect(settle(startupStates['anonymous']!, JoinFlowStatus.none, '/?from=%2Fassignment'), Routes.welcome);
    });

    test('external or unknown targets are ignored (no open redirect)', () {
      for (final from in ['https://evil.example', '//evil.example', '/', '/nope', 'javascript:alert(1)']) {
        expect(safeDeepLink(from), isNull, reason: from);
      }
      expect(
        settle(startupStates['anonymous']!, JoinFlowStatus.none, '/?from=https%3A%2F%2Fevil.example'),
        Routes.welcome,
      );
    });
  });

  group('recovery code route', () {
    final anon = startupStates['anonymous']!;

    test('no pending join (refresh / deep link / hot restart) -> /join', () {
      expect(settle(anon, JoinFlowStatus.none, Routes.joinRecoveryCode), Routes.join);
      expect(settle(anon, JoinFlowStatus.none, '/?from=%2Fjoin%2Frecovery-code'), Routes.join);
    });

    test('pending join stays on the code screen', () {
      expect(settle(anon, JoinFlowStatus.pending, Routes.joinRecoveryCode), Routes.joinRecoveryCode);
    });

    test('pending join: other anonymous routes are sent back to the code', () {
      for (final route in [Routes.welcome, Routes.join, Routes.recover]) {
        expect(settle(anon, JoinFlowStatus.pending, route), Routes.joinRecoveryCode, reason: route);
      }
    });

    test('finished unsaved join leaves to /welcome', () {
      expect(settle(anon, JoinFlowStatus.finishedUnsaved, Routes.joinRecoveryCode), Routes.welcome);
    });

    test('participant never sees the code screen', () {
      expect(settle(startupStates['participant']!, JoinFlowStatus.pending, Routes.joinRecoveryCode), Routes.assignment);
    });
  });

  test('unknown path goes to the default route', () {
    expect(settle(startupStates['anonymous']!, JoinFlowStatus.none, '/nope'), Routes.welcome);
    expect(settle(startupStates['participant']!, JoinFlowStatus.none, '/nope'), Routes.assignment);
  });

  test('/organizer is reachable from both settled states', () {
    expect(settle(startupStates['anonymous']!, JoinFlowStatus.none, Routes.organizer), Routes.organizer);
    expect(settle(startupStates['participant']!, JoinFlowStatus.none, Routes.organizer), Routes.organizer);
  });
}
