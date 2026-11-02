import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/app_session.dart';

/// Decides who the user is on this device. Single source of truth for the
/// router guards.
///
/// Reads participant credentials from secure storage only; no network calls.
/// The assignment screen validates the stored identity with the server.
///
/// States:
/// * `AsyncLoading`: still reading storage (router stays on `/`).
/// * `AsyncData(AnonymousSession)`: no participant on this device.
/// * `AsyncData(ParticipantSession)`: credentials found.
/// * `AsyncError`: secure storage itself failed (e.g. Keychain locked).
///   Credentials are NOT deleted; [retry] reads again.
///
/// Concurrency: every state change bumps a generation counter. An async read
/// only writes its result if no newer change happened while it was running,
/// so the LAST requested change always wins:
/// * two quick [syncFromStorage] calls: only the second result is applied;
/// * [markAnonymous] during a [syncFromStorage]: the late read (which may
///   have seen the identity before it was deleted) is discarded.
class StartupController extends AsyncNotifier<AppSession> {
  int _generation = 0;

  @override
  Future<AppSession> build() {
    _generation++;
    return _readSession();
  }

  Future<AppSession> _readSession() async {
    final store = ref.read(credentialStoreProvider);
    final credentials = await store.readParticipant();
    if (credentials == null) return const AnonymousSession();
    return ParticipantSession(credentials);
  }

  /// Re-reads secure storage after a storage error. Shows the splash screen
  /// while reading.
  Future<void> retry() async {
    final generation = ++_generation;
    state = const AsyncLoading<AppSession>();
    final result = await AsyncValue.guard(_readSession);
    if (generation == _generation) state = result;
  }

  /// Re-reads secure storage WITHOUT passing through a loading state, so the
  /// router moves straight from the current screen to the right one.
  ///
  /// Called after a repository saved an identity (join confirmed, recovery).
  /// A storage error here becomes `AsyncError` (splash with retry).
  ///
  /// Returns the session that is current when the call completes (which may
  /// come from a newer call that superseded this one).
  Future<AsyncValue<AppSession>> syncFromStorage() async {
    // Let the initial build finish first: its completion would otherwise
    // overwrite the result of this read.
    try {
      await future;
    } on Object {
      // A failed initial build is replaced by this read.
    }
    final generation = ++_generation;
    final result = await AsyncValue.guard(_readSession);
    if (generation == _generation) state = result;
    return state;
  }

  /// The identity was removed from this device ("leave this device").
  /// Supersedes any read still in flight.
  void markAnonymous() {
    _generation++;
    state = const AsyncData<AppSession>(AnonymousSession());
  }
}

final startupControllerProvider = AsyncNotifierProvider<StartupController, AppSession>(
  StartupController.new,
  name: 'startupControllerProvider',
);
