import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_session.dart';
import 'routes.dart';

/// Query parameter on `/` that remembers where the user was going while the
/// startup state loads (browser refresh, deep link, invite link).
const String fromParam = 'from';

/// Routes that only make sense without a participant identity.
const Set<String> anonymousOnlyRoutes = {
  Routes.welcome,
  Routes.join,
  Routes.joinRecoveryCode,
  Routes.recover,
};

/// Routes that need a participant identity on this device.
const Set<String> participantOnlyRoutes = {Routes.assignment};

/// Every route a deep link may target. `/` is excluded on purpose.
const Set<String> deepLinkableRoutes = {
  ...anonymousOnlyRoutes,
  ...participantOnlyRoutes,
  Routes.organizer,
};

/// Every route the router knows.
const Set<String> knownRoutes = {Routes.splash, ...deepLinkableRoutes};

/// Where the join flow stands, as far as routing is concerned.
enum JoinFlowStatus {
  /// No join in progress.
  none,

  /// A join succeeded and its recovery code has not been confirmed yet.
  pending,

  /// The user confirmed the code of a join that could NOT be saved on this
  /// device. They leave the flow to `/welcome` (never back to the join form:
  /// the participant already exists).
  finishedUnsaved,
}

/// Pure redirect logic for the app router. Returns the location to go to, or
/// null to stay. Unit-tested exhaustively for loops (see route_guard_test).
///
/// Inputs:
/// * [startup]: the startup controller state.
/// * [join]: the join flow status.
/// * [uri]: the location being navigated to.
///
/// Rules:
/// 1. Startup not settled (loading, error, refreshing): go to `/`, remembering
///    the target in `?from=` (unless already on `/`).
/// 2. On `/` once settled: go to the remembered target if it is a known
///    internal route, else the default (`/assignment` or `/welcome`), then
///    apply rule 3 to it.
/// 3. Unknown path (typo, stale bookmark): go to `/`, which picks the default.
/// 4. Guards:
///    * participant on an anonymous-only route        -> `/assignment`
///    * anonymous on a participant-only route         -> `/welcome`
///    * anonymous on `/join/recovery-code`:
///      - pending          -> stay
///      - finishedUnsaved  -> `/welcome`
///      - none             -> `/join` (refresh / deep link: the code is gone;
///                            never show an empty screen)
///    * anonymous on another anonymous-only route while pending
///      -> `/join/recovery-code` (browser back must not skip confirming, or a
///      second join could overwrite the stored identity)
///
/// Every chain ends in at most 3 redirects and never revisits a location.
String? resolveRedirect({
  required AsyncValue<AppSession> startup,
  required JoinFlowStatus join,
  required Uri uri,
}) {
  final path = uri.path;
  final atSplash = path == Routes.splash;

  // Rule 1. Only a settled AsyncData is routed on. In Riverpod 2 a refresh
  // over existing data is an AsyncData with isLoading == true.
  if (startup is! AsyncData<AppSession> || startup.isLoading || startup.hasError) {
    if (atSplash) return null;
    return Uri(path: Routes.splash, queryParameters: {fromParam: uri.toString()}).toString();
  }

  // Promoted: .value is non-nullable, requireValue never needed.
  final AppSession session = startup.value;

  // Rule 2.
  if (atSplash) {
    final target = safeDeepLink(uri.queryParameters[fromParam]);
    if (target == null) {
      return switch (session) {
        ParticipantSession() => Routes.assignment,
        AnonymousSession() => Routes.welcome,
      };
    }
    return _guard(session, join, target.path) ?? target.toString();
  }

  // Rule 3.
  if (!knownRoutes.contains(path)) return Routes.splash;

  // Rule 4.
  return _guard(session, join, path);
}

String? _guard(AppSession session, JoinFlowStatus join, String path) {
  switch (session) {
    case ParticipantSession():
      return anonymousOnlyRoutes.contains(path) ? Routes.assignment : null;
    case AnonymousSession():
      if (participantOnlyRoutes.contains(path)) return Routes.welcome;
      if (path == Routes.joinRecoveryCode) {
        return switch (join) {
          JoinFlowStatus.pending => null,
          JoinFlowStatus.finishedUnsaved => Routes.welcome,
          JoinFlowStatus.none => Routes.join,
        };
      }
      if (join == JoinFlowStatus.pending && anonymousOnlyRoutes.contains(path)) {
        return Routes.joinRecoveryCode;
      }
      return null;
  }
}

/// Accepts only a relative, known, internal route (keeps its query, e.g.
/// `/join?code=ABC234`). Rejects absolute URLs, `//host` links, unknown paths
/// and `/` itself, so `?from=` can never be used as an open redirect or loop.
Uri? safeDeepLink(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (!deepLinkableRoutes.contains(uri.path)) return null;
  return uri;
}
