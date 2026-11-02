import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/participant_api_models.dart';
import '../../startup/startup_controller.dart';

/// Loads the assignment for the identity stored on this device.
///
/// * Never deletes the stored identity on errors: the screen shows the error
///   and offers "Leave this device" for identity errors (404/403), "Try again"
///   for everything else.
/// * [refresh] keeps the current assignment visible while reloading. A failed
///   refresh keeps it too (AsyncError WITH the previous value); the screen
///   shows that error as a temporary message.
/// * One request at a time: refresh calls made while the initial load or
///   another refresh is running share that request instead of starting a
///   new one (and callers awaiting refresh() wait for it).
class AssignmentController extends AutoDisposeAsyncNotifier<Assignment> {
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  Future<Assignment> build() {
    // The screen can close while a refresh is running (auto-dispose); never
    // write state after that.
    ref.onDispose(() => _disposed = true);
    final load = ref.read(participantRepositoryProvider).getMyAssignment();
    _track(load.then<void>((_) {}, onError: (Object _) {}));
    return load;
  }

  /// Reloads the assignment. Concurrent calls share one request.
  Future<void> refresh() => _inFlight ?? _track(_refresh());

  Future<void> _refresh() async {
    final repository = ref.read(participantRepositoryProvider);
    state = const AsyncLoading<Assignment>().copyWithPrevious(state);
    final result = await AsyncValue.guard(repository.getMyAssignment);
    if (_disposed) return;
    // Explicit copyWithPrevious: keep the last good assignment on failure.
    state = result.copyWithPrevious(state);
  }

  Future<void> _track(Future<void> request) {
    _inFlight = request;
    unawaited(
      request.then<void>(
        (_) {},
        onError: (Object _) {}, // errors are reported through state
      ).whenComplete(() {
        if (identical(_inFlight, request)) _inFlight = null;
      }),
    );
    return request;
  }

  /// Recovery code stored on this device, or null if none was saved.
  Future<String?> storedRecoveryCode() => ref.read(participantRepositoryProvider).storedRecoveryCode();

  /// Removes the identity from this device (no server call), then marks the
  /// app anonymous so the router moves to `/welcome`.
  Future<void> leaveDevice() async {
    await ref.read(participantRepositoryProvider).clearIdentity();
    ref.read(startupControllerProvider.notifier).markAnonymous();
  }
}

final assignmentControllerProvider = AsyncNotifierProvider.autoDispose<AssignmentController, Assignment>(
  AssignmentController.new,
  name: 'assignmentControllerProvider',
);
