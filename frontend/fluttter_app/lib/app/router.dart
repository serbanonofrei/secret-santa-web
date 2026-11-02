import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/app_session.dart';
import '../features/participant/assignment/assignment_screen.dart';
import '../features/participant/join/join_controller.dart';
import '../features/participant/join/join_screen.dart';
import '../features/participant/join/recovery_code_screen.dart';
import '../features/participant/recover/recover_screen.dart';
import '../features/startup/splash_screen.dart';
import '../features/startup/startup_controller.dart';
import '../features/welcome/welcome_screen.dart';
import '../shared/widgets/placeholder_screen.dart';
import 'route_guard.dart';
import 'routes.dart';

export 'routes.dart';

/// App router.
///
/// All participant navigation is decided by [resolveRedirect] from two
/// states: [startupControllerProvider] (who is on this device) and
/// [joinControllerProvider] (is a join waiting for its recovery code to be
/// confirmed). Screens change state; they never navigate for these flows.
/// See `route_guard.dart` for the rules and the loop-freedom argument.
///
/// Phase 5 adds the organizer guards.
final routerProvider = Provider<GoRouter>(
  (ref) {
    final refresh = _GuardRefreshListenable(ref);
    ref.onDispose(refresh.dispose);

    final router = GoRouter(
      initialLocation: Routes.splash,
      debugLogDiagnostics: kDebugMode,
      refreshListenable: refresh,
      // Unknown paths are sent to `/` by the guard, so this only shows if the
      // guard itself is bypassed.
      errorBuilder: (context, state) => const SplashScreen(),
      redirect: (context, state) => resolveRedirect(
        startup: ref.read(startupControllerProvider),
        join: joinFlowStatusOf(ref.read(joinControllerProvider)),
        uri: state.uri,
      ),
      routes: [
        GoRoute(
          path: Routes.splash,
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: Routes.welcome,
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: Routes.join,
          builder: (context, state) => JoinScreen(initialInviteCode: state.uri.queryParameters['code']),
          routes: [
            GoRoute(
              // Full path: /join/recovery-code
              path: 'recovery-code',
              builder: (context, state) => const RecoveryCodeScreen(),
            ),
          ],
        ),
        GoRoute(
          path: Routes.recover,
          builder: (context, state) => const RecoverScreen(),
        ),
        GoRoute(
          path: Routes.assignment,
          builder: (context, state) => const AssignmentScreen(),
        ),
        GoRoute(
          path: Routes.organizer,
          builder: (context, state) => const PlaceholderScreen(title: 'Organizer', phase: 'phase 5'),
        ),
      ],
    );
    ref.onDispose(router.dispose);
    return router;
  },
  name: 'routerProvider',
);

/// Re-runs the router redirect whenever an input of [resolveRedirect] changes.
class _GuardRefreshListenable extends ChangeNotifier {
  _GuardRefreshListenable(Ref ref) {
    _subscriptions = [
      ref.listen<AsyncValue<AppSession>>(startupControllerProvider, (_, __) => notifyListeners()),
      // Only the routing-relevant part of the join state: typing in the form
      // (idle <-> failed) must not re-run redirects.
      ref.listen<JoinFlowStatus>(
        joinControllerProvider.select(joinFlowStatusOf),
        (_, __) => notifyListeners(),
      ),
    ];
  }

  late final List<ProviderSubscription<Object?>> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    super.dispose();
  }
}
